local app_numbers = require("desktop_manager.core.app_numbers")
local focus_before_press = require("desktop_manager.macos.focus_before_press")
local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")
local new_windows = require("desktop_manager.macos.new_windows")
local read_desktops = require("desktop_manager.macos.read_desktops")
local track_windows = require("desktop_manager.macos.track_windows")

local app_switcher = {}

---The work that runs within a press once its desktop shows, and ends with an error message or nil.
---@alias AfterShown fun(on_done: fun(error_message: string|nil))

---What the list and the search need from the controller to bring a window to the front.
---Each press that takes time shows the busy message, and gives "Desktop Manager is still
---switching" while a switch, a restore or another press runs, so that the message of that work
---stays.
---@class SwitcherContext
---@field timing Timing
---@field show_space fun(space_id: integer, after_shown: AfterShown|nil,
---on_done: fun(error_message: string|nil), chosen_window: ChosenWindow|nil) shows the desktop
---through Mission Control, and then runs `after_shown` within the same press, and with a chosen
---window it may first focus another window of the application of the chosen window
---@field run_press fun(text: string, press: fun(on_pressed: fun(error_message: string|nil)),
---on_done: fun(error_message: string|nil)) runs a press that takes time, such as the opening of a
---window, with the text as the busy message
---@field refuse_while_busy fun(): boolean shows "Desktop Manager is still switching" and returns
---true while a switch, a restore or a press runs

---The kind of an hs.application with a Dock icon.
local REGULAR_APPLICATION_KIND = 1

---The accessibility role of a window, which a sheet, a drawer or another element lacks.
local WINDOW_ROLE = "AXWindow"

---Whether each application is hidden, by bundle id.
---`hs.application:isHidden()` asks the application through accessibility, so an application
---enters the table the first time that the list or the search asks about it, and the events of
---`hs.application.watcher` keep its entry current afterwards.
---@alias HiddenStates table<string, boolean>

---What the list or the search knows of the hidden applications while it opens.
---@class HiddenApplications
---@field setting string a value of hidden_application_windows
---@field is_hidden fun(bundle_id: string, application: table|nil): boolean whether the application
---is hidden

---The running application of the bundle id, found without the search of `hs.application.get`
---through every window of every application when no application of the bundle id runs.
---@param bundle_id string
---@return table|nil an hs.application
local function find_running_application(bundle_id)
    return hs.application.applicationsForBundleID(bundle_id)[1]
end

---Updates the hidden states on an event of `hs.application.watcher`.
---A quit forgets every state, so that an application that starts again is asked once more.
---@param hidden_states HiddenStates
---@param event any the event of the watcher
---@param application table|nil the hs.application of the event
function app_switcher.update_hidden_states(hidden_states, event, application)
    if event == hs.application.watcher.terminated then
        for bundle_id in pairs(hidden_states) do
            hidden_states[bundle_id] = nil
        end
    elseif application and event == hs.application.watcher.hidden then
        hidden_states[track_windows.bundle_id_of(application)] = true
    elseif application and event == hs.application.watcher.unhidden then
        hidden_states[track_windows.bundle_id_of(application)] = false
    end
end

---Answers whether an application is hidden from the hidden states, and asks the application
---through accessibility only when the states do not hold it yet.
---@param setting string a value of hidden_application_windows
---@param hidden_states HiddenStates
---@return HiddenApplications
function app_switcher.read_hidden_applications(setting, hidden_states)
    return {
        setting = setting,
        is_hidden = function(bundle_id, application)
            if hidden_states[bundle_id] == nil then
                local running = application or find_running_application(bundle_id)
                if not running then
                    return false
                end
                hidden_states[bundle_id] = running:isHidden()
            end
            return hidden_states[bundle_id]
        end,
    }
end

---@param window table an hs.window
---@return boolean
local function is_standard_window(window)
    return window:isStandard()
end

---@param window table an hs.window
---@return boolean
local function is_window(window)
    return window:role() == WINDOW_ROLE
end

---@param _ HiddenApplications
---@return boolean
local function keep_always(_)
    return true
end

---@param _ HiddenApplications
---@return table[]
local function list_no_windows(_)
    return {}
end

---@param _ HiddenApplications
---@return boolean
local function mark_never(_)
    return false
end

---@param hidden HiddenApplications
---@param bundle_id string
---@param application table|nil an hs.application
---@return boolean
local function mark_if_hidden(hidden, bundle_id, application)
    return hidden.is_hidden(bundle_id, application)
end

---@param hidden HiddenApplications
---@param bundle_id string
---@param application table|nil an hs.application
---@return boolean
local function keep_unless_hidden(hidden, bundle_id, application)
    return not hidden.is_hidden(bundle_id, application)
end

---@param hidden HiddenApplications
---@return table[] the hs.window of every window of each hidden application with a Dock icon
local function list_windows_of_hidden_applications(hidden)
    local windows = {}
    for _, application in ipairs(hs.application.runningApplications()) do
        local bundle_id = track_windows.bundle_id_of(application)
        if
            application:kind() == REGULAR_APPLICATION_KIND
            and hidden.is_hidden(bundle_id, application)
        then
            for _, window in ipairs(application:allWindows()) do
                if is_window(window) then
                    table.insert(windows, window)
                end
            end
        end
    end
    return windows
end

---What each value of hidden_application_windows does in the list and the search.
---`keeps_found` says whether a window of the application that the window filter or the list of the
---window server found stays.
---`select_joining_test` gives the test by which a window of `allWindows` of the application joins
---the list, or nil when the list reads no `allWindows` of it.
---`list_unfiltered_windows` gives the windows that the search adds to those of the window filter.
---`marks_hidden` says whether the list marks the application as hidden, so that a press unhides it.
---Under the value that marks it, the list shows no window of a hidden application.
---@class HiddenWindowsRule
---@field keeps_found fun(hidden: HiddenApplications, bundle_id: string, application: table|nil):
---boolean
---@field select_joining_test fun(hidden: HiddenApplications, bundle_id: string,
---application: table|nil): (fun(window: table): boolean)|nil
---@field list_unfiltered_windows fun(hidden: HiddenApplications): table[]
---@field marks_hidden fun(hidden: HiddenApplications, bundle_id: string,
---application: table|nil): boolean

---@type table<string, HiddenWindowsRule>
local HIDDEN_WINDOWS_RULES = {
    [hidden_application_windows.LEAVE_OUT] = {
        keeps_found = keep_unless_hidden,
        select_joining_test = function(hidden, bundle_id, application)
            if hidden.is_hidden(bundle_id, application) then
                return nil
            end
            return is_standard_window
        end,
        list_unfiltered_windows = list_no_windows,
        marks_hidden = mark_if_hidden,
    },
    [hidden_application_windows.LIST_WHERE_FOUND] = {
        keeps_found = keep_always,
        select_joining_test = function()
            return is_standard_window
        end,
        list_unfiltered_windows = list_no_windows,
        marks_hidden = mark_never,
    },
    [hidden_application_windows.LIST_ALL] = {
        keeps_found = keep_always,
        select_joining_test = function(hidden, bundle_id, application)
            if hidden.is_hidden(bundle_id, application) then
                return is_window
            end
            return is_standard_window
        end,
        list_unfiltered_windows = list_windows_of_hidden_applications,
        marks_hidden = mark_never,
    },
}

---The windows of the window filter that the list and the search show under the setting.
---@param hidden HiddenApplications
---@param filter_windows table[] the hs.window objects of the window filter
---@return table[]
function app_switcher.keep_shown_filter_windows(hidden, filter_windows)
    local rule, kept = HIDDEN_WINDOWS_RULES[hidden.setting], {}
    for _, window in ipairs(filter_windows) do
        local application = window:application()
        if rule.keeps_found(hidden, track_windows.bundle_id_of(application), application) then
            table.insert(kept, window)
        end
    end
    return kept
end

---The windows that accessibility does not reach that the list and the search show under the
---setting.
---@param hidden HiddenApplications
---@param unreached_windows ServerWindow[]
---@return ServerWindow[]
function app_switcher.keep_shown_unreached_windows(hidden, unreached_windows)
    local rule, kept = HIDDEN_WINDOWS_RULES[hidden.setting], {}
    for _, window in ipairs(unreached_windows) do
        if rule.keeps_found(hidden, window.bundle_id, nil) then
            table.insert(kept, window)
        end
    end
    return kept
end

---The windows of the search: the windows of the window filter that the setting keeps, the most
---recently focused first, and after them the windows that the setting adds, which the window filter
---leaves out.
---`search_windows.list_entries` drops a window that both parts hold.
---@param hidden HiddenApplications
---@param filter_windows table[] the hs.window objects of the window filter
---@return table[] hs.window objects
function app_switcher.list_search_windows(hidden, filter_windows)
    local windows = app_switcher.keep_shown_filter_windows(hidden, filter_windows)
    for _, window in ipairs(HIDDEN_WINDOWS_RULES[hidden.setting].list_unfiltered_windows(hidden)) do
        table.insert(windows, window)
    end
    return windows
end

---Every window of the application that Hammerspoon knows and the setting shows, on any desktop.
---The windows of the window filter come first, the most recently focused one at the front.
---@param bundle_id string
---@param filter_windows table[] the hs.window objects of the window filter that the setting keeps
---@param hidden HiddenApplications
---@return table[] hs.window objects
---@return table|nil the running hs.application of the bundle id
function app_switcher.list_windows(bundle_id, filter_windows, hidden)
    local windows, is_listed = {}, {}
    local function add(window)
        local window_id = window:id()
        if
            window_id
            and window_id > 0
            and not is_listed[window_id]
            and track_windows.bundle_id_of(window:application()) == bundle_id
        then
            is_listed[window_id] = true
            table.insert(windows, window)
        end
    end
    for _, window in ipairs(filter_windows) do
        add(window)
    end
    local application = find_running_application(bundle_id)
    local joins = application
        and HIDDEN_WINDOWS_RULES[hidden.setting].select_joining_test(hidden, bundle_id, application)
    if joins then
        for _, window in ipairs(application:allWindows()) do
            if joins(window) then
                add(window)
            end
        end
    end
    return windows, application
end

---The application of the number for the list, with its windows in the order of the window ids, the
---windows that accessibility does not reach included.
---The first press selects the window after the focused one when the application is in front, and
---otherwise the window of the application that had the focus last.
---@param entry AppNumber
---@param filter_windows table[] the hs.window objects of the window filter that the setting keeps
---@param unreached_windows ServerWindow[] the windows that accessibility does not reach, which the
---setting keeps
---@param screen_uuid_by_space table<integer, string> the display of each desktop
---@param hidden HiddenApplications
---@return SwitchApplication
---@return table<integer, table> the hs.window of each window id that accessibility reaches
function app_switcher.describe_application(
    entry,
    filter_windows,
    unreached_windows,
    screen_uuid_by_space,
    hidden
)
    local windows, application = app_switcher.list_windows(entry.bundle_id, filter_windows, hidden)
    local window_by_id, window_ids, unreached_titles = {}, {}, {}
    for _, window in ipairs(windows) do
        window_by_id[window:id()] = window
        table.insert(window_ids, window:id())
    end
    for _, window in ipairs(unreached_windows) do
        if window.bundle_id == entry.bundle_id and not window_by_id[window.window_id] then
            unreached_titles[window.window_id] = window.title
            table.insert(window_ids, window.window_id)
        end
    end
    table.sort(window_ids)
    local first_window_id = windows[1] and windows[1]:id()
    local frontmost = hs.application.frontmostApplication()
    local focused = hs.window.focusedWindow()
    if
        frontmost
        and focused
        and track_windows.bundle_id_of(frontmost) == entry.bundle_id
        and window_by_id[focused:id()]
    then
        first_window_id = app_numbers.find_next_window_id(window_ids, focused:id())
    end
    local switch_windows, first_window_index = {}, 0
    for index, window_id in ipairs(window_ids) do
        local space_id = read_desktops.find_window_space_id(window_id)
        local window = window_by_id[window_id]
        table.insert(switch_windows, {
            window_id = window_id,
            title = window and (window:title() or "") or unreached_titles[window_id],
            screen_uuid = space_id and screen_uuid_by_space[space_id],
        })
        if window_id == first_window_id then
            first_window_index = index
        end
    end
    return {
        number = entry.number,
        bundle_id = entry.bundle_id,
        app_name = entry.app_name,
        windows = switch_windows,
        first_window_index = first_window_index,
        is_hidden = HIDDEN_WINDOWS_RULES[hidden.setting].marks_hidden(
            hidden,
            entry.bundle_id,
            application
        ),
    },
        window_by_id
end

---Unhides the application of the window, unminimizes the window and focuses it.
---@param window table an hs.window
local function focus_window(window)
    local application = window:application()
    if application and application:isHidden() then
        application:unhide()
    end
    if window:isMinimized() then
        window:unminimize()
    end
    window:focus()
end

---Brings the window to the front: shows its desktop through the context when another desktop
---shows, then unhides its application, unminimizes it and focuses it.
---@param window table an hs.window
---@param context SwitcherContext
---@param on_done fun(error_message: string|nil)
function app_switcher.bring_to_front(window, context, on_done)
    local space_id = read_desktops.find_window_space_id(window:id())
    if space_id and not read_desktops.is_space_active(space_id) then
        context.show_space(space_id, nil, function(error_message)
            if error_message then
                on_done(error_message)
                return
            end
            focus_window(window)
            on_done(nil)
        end, focus_before_press.choose(window))
        return
    end
    focus_window(window)
    on_done(nil)
end

---Shows the desktop of a window that accessibility does not reach, waits until accessibility
---reaches the window there, and brings it to the front, all within one press, so that no switch
---starts during the wait.
---@param window ServerWindow
---@param context SwitcherContext
---@param on_done fun(error_message: string|nil)
function app_switcher.reach_window(window, context, on_done)
    local timeout_seconds = context.timing.window_reach_timeout_seconds
    context.show_space(window.space_id, function(on_reached)
        track_windows.wait_until_reached({ window }, timeout_seconds, function(reached)
            local reached_window = reached[window.window_id]
            if not reached_window then
                on_reached(
                    string.format(
                        "%s window %q did not appear within %g seconds after its desktop showed",
                        window.app_name,
                        window.title,
                        timeout_seconds
                    )
                )
                return
            end
            focus_window(reached_window)
            on_reached(nil)
        end)
    end, on_done, { bundle_id = window.bundle_id, window_id = window.window_id })
end

---@param entry AppNumber
---@param context SwitcherContext
---@param on_done fun(error_message: string|nil)
local function open_new_window(entry, context, on_done)
    context.run_press(
        string.format("Opening a window of %s… please wait", entry.app_name),
        function(on_opened)
            local record = { bundle_id = entry.bundle_id, app_name = entry.app_name, title = "" }
            new_windows
                .start_session(context.timing)
                :provide_window(record, function(window, error_message)
                    if not window then
                        on_opened(error_message)
                        return
                    end
                    window:focus()
                    on_opened(nil)
                end)
        end,
        on_done
    )
end

---Brings the selected window of the application of the number to the front.
---Without a selected window, a recorded window on a desktop that Hammerspoon has not seen is
---reached by showing that desktop, and an application without such a window gets a new window.
---@param entry AppNumber
---@param window table|nil the selected hs.window
---@param recorded_window_ids integer[] the windows of the application that some profile recorded
---@param context SwitcherContext
---@param on_done fun(error_message: string|nil)
function app_switcher.switch_to_selection(entry, window, recorded_window_ids, context, on_done)
    if window then
        app_switcher.bring_to_front(window, context, on_done)
        return
    end
    for _, window_id in ipairs(recorded_window_ids) do
        local space_id = read_desktops.find_window_space_id(window_id)
        if space_id then
            context.show_space(space_id, nil, function(error_message)
                local reached = app_switcher.list_windows(
                    entry.bundle_id,
                    {},
                    app_switcher.read_hidden_applications(
                        hidden_application_windows.LIST_WHERE_FOUND,
                        {}
                    )
                )
                if error_message or #reached == 0 then
                    open_new_window(entry, context, on_done)
                    return
                end
                app_switcher.bring_to_front(reached[1], context, on_done)
            end, { bundle_id = entry.bundle_id, window_id = window_id })
            return
        end
    end
    open_new_window(entry, context, on_done)
end

---@param app_name string
---@param timeout_seconds number
---@return string the failure of a wait after an unhide that ends without a standard window
local function describe_no_standard_window(app_name, timeout_seconds)
    return string.format(
        "%s showed no standard window in the %g-second wait after its unhide",
        app_name,
        timeout_seconds
    )
end

---Unhides the application of the number, which the list marked as hidden, waits until it shows a
---standard window, and brings its main window, or else its first standard window, to the front,
---without a new window.
---When the main window, or else the first window, lies on a desktop out of view, that desktop
---shows first while the application is still hidden, because accessibility may lose a window on a
---desktop that has not shown once its application unhides.
---The wait and the focus then run within the press that shows the desktop.
---Otherwise the wait runs within a press of its own.
---Either way no switch starts during the wait.
---An application without any window takes the way of `switch_to_selection` without a window.
---@param entry AppNumber
---@param recorded_window_ids integer[] the windows of the application that some profile recorded
---@param context SwitcherContext
---@param on_done fun(error_message: string|nil)
function app_switcher.unhide_application(entry, recorded_window_ids, context, on_done)
    local application = find_running_application(entry.bundle_id)
    local windows = application and application:allWindows() or {}
    if #windows == 0 then
        app_switcher.switch_to_selection(entry, nil, recorded_window_ids, context, on_done)
        return
    end
    local timeout_seconds = context.timing.window_reach_timeout_seconds
    local chosen = application:mainWindow() or windows[1]
    local space_id = read_desktops.find_window_space_id(chosen:id())
    if space_id and not read_desktops.is_space_active(space_id) then
        context.show_space(space_id, function(on_shown)
            application:unhide()
            track_windows.wait_until_window_standard(chosen, timeout_seconds, function(window)
                if not window then
                    on_shown(describe_no_standard_window(entry.app_name, timeout_seconds))
                    return
                end
                focus_window(window)
                on_shown(nil)
            end)
        end, on_done)
        return
    end
    local shown_window = nil
    context.run_press(
        string.format("Unhiding %s… please wait", entry.app_name),
        function(on_unhidden)
            application:unhide()
            track_windows.wait_until_standard(application, timeout_seconds, function(window)
                if not window then
                    on_unhidden(describe_no_standard_window(entry.app_name, timeout_seconds))
                    return
                end
                shown_window = window
                on_unhidden(nil)
            end)
        end,
        function(error_message)
            if error_message then
                on_done(error_message)
                return
            end
            app_switcher.bring_to_front(shown_window, context, on_done)
        end
    )
end

return app_switcher
