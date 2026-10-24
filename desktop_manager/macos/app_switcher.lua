local app_numbers = require("desktop_manager.core.app_numbers")
local focus_before_press = require("desktop_manager.macos.focus_before_press")
local hidden_application_filter = require("desktop_manager.macos.hidden_application_filter")
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

---The application of the number for the list, with its windows in the order of the window ids, the
---windows that accessibility does not reach included, and the window that the first press selects,
---as `app_numbers.find_first_selection_index` chooses it.
---@param entry AppNumber
---@param filter_windows table[] the hs.window objects of the window filter that the setting keeps
---@param unreached_windows ServerWindow[] the windows that accessibility does not reach, which the
---setting keeps
---@param screen_uuid_by_space table<integer, string> the display of each desktop
---@param hidden HiddenApplications
---@return NumberedApplication
---@return table<integer, table> the hs.window of each window id that accessibility reaches
function app_switcher.describe_application(
    entry,
    filter_windows,
    unreached_windows,
    screen_uuid_by_space,
    hidden
)
    local windows, application =
        hidden_application_filter.list_windows(entry.bundle_id, filter_windows, hidden)
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
    local last_focused_window_id = windows[1] and windows[1]:id()
    local is_application_frontmost = focus_before_press.is_frontmost(entry.bundle_id)
    local focused = hs.window.focusedWindow()
    local focused_window_id = nil
    if is_application_frontmost and focused and window_by_id[focused:id()] then
        focused_window_id = focused:id()
    end
    local switch_windows = {}
    for _, window_id in ipairs(window_ids) do
        local space_id = read_desktops.find_window_space_id(window_id)
        local window = window_by_id[window_id]
        table.insert(switch_windows, {
            window_id = window_id,
            title = window and (window:title() or "") or unreached_titles[window_id],
            screen_uuid = space_id and screen_uuid_by_space[space_id],
        })
    end
    return {
        number = entry.number,
        bundle_id = entry.bundle_id,
        app_name = entry.app_name,
        windows = switch_windows,
        first_window_index = app_numbers.find_first_selection_index(
            window_ids,
            last_focused_window_id,
            focused_window_id
        ),
        is_hidden = hidden_application_filter.marks_hidden(hidden, entry.bundle_id, application),
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
                local reached = hidden_application_filter.list_windows(
                    entry.bundle_id,
                    {},
                    hidden_application_filter.read_hidden_applications(
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
    local application = track_windows.find_running_application(entry.bundle_id)
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
