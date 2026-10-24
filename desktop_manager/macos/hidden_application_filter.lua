local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")
local track_windows = require("desktop_manager.macos.track_windows")

---The windows of the hidden applications that the list and the search show under the setting
---hidden_application_windows, and whether each application is hidden.
local hidden_application_filter = {}

---The accessibility role of a window, which a sheet, a drawer or another element lacks.
local WINDOW_ROLE = "AXWindow"

---Whether each application is hidden, by bundle id.
---`hs.application:isHidden()` asks the application through accessibility, so an application
---enters the table the first time that the list or the search asks about it, and the events of
---`hs.application.watcher` keep its entry current afterwards, until the application quits.
---@alias HiddenStates table<string, boolean>

---What the list or the search knows of the hidden applications while it opens.
---@class HiddenApplications
---@field setting string a value of hidden_application_windows
---@field is_hidden fun(bundle_id: string, application: table|nil): boolean whether the application
---is hidden

---Forgets the state of the application that quit, so that the application is asked once more when
---it starts again.
---A quit that names no application by its bundle id or its name forgets every state.
---@param hidden_states HiddenStates
---@param bundle_id string the application that quit, as `track_windows.bundle_id_of` gives it
local function forget_quit_application(hidden_states, bundle_id)
    if bundle_id ~= track_windows.UNKNOWN_BUNDLE_ID then
        hidden_states[bundle_id] = nil
        return
    end
    for known_bundle_id in pairs(hidden_states) do
        hidden_states[known_bundle_id] = nil
    end
end

---Updates the hidden states on an event of `hs.application.watcher`.
---The hidden states are a cache of `hs.application:isHidden()`, which these events keep current.
---@param hidden_states HiddenStates
---@param event any the event of the watcher
---@param application table|nil the hs.application of the event
function hidden_application_filter.update_hidden_states(hidden_states, event, application)
    local bundle_id = track_windows.bundle_id_of(application)
    if event == hs.application.watcher.terminated then
        forget_quit_application(hidden_states, bundle_id)
    elseif application and event == hs.application.watcher.hidden then
        hidden_states[bundle_id] = true
    elseif application and event == hs.application.watcher.unhidden then
        hidden_states[bundle_id] = false
    end
end

---Answers whether an application is hidden from the hidden states, and asks the application
---through accessibility only when the states do not hold it yet.
---@param setting string a value of hidden_application_windows
---@param hidden_states HiddenStates
---@return HiddenApplications
function hidden_application_filter.read_hidden_applications(setting, hidden_states)
    return {
        setting = setting,
        is_hidden = function(bundle_id, application)
            if hidden_states[bundle_id] == nil then
                local running = application or track_windows.find_running_application(bundle_id)
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
            application:kind() == track_windows.REGULAR_APPLICATION_KIND
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

---@alias JoiningTest fun(window: table): boolean

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
---application: table|nil): JoiningTest|nil
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
function hidden_application_filter.keep_shown_filter_windows(hidden, filter_windows)
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
function hidden_application_filter.keep_shown_unreached_windows(hidden, unreached_windows)
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
function hidden_application_filter.list_search_windows(hidden, filter_windows)
    local windows = hidden_application_filter.keep_shown_filter_windows(hidden, filter_windows)
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
function hidden_application_filter.list_windows(bundle_id, filter_windows, hidden)
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
    local application = track_windows.find_running_application(bundle_id)
    if application then
        local joins =
            HIDDEN_WINDOWS_RULES[hidden.setting].select_joining_test(hidden, bundle_id, application)
        if joins then
            for _, window in ipairs(application:allWindows()) do
                if joins(window) then
                    add(window)
                end
            end
        end
    end
    return windows, application
end

---Whether the list marks the application as hidden under the setting, so that a press unhides it.
---@param hidden HiddenApplications
---@param bundle_id string
---@param application table|nil an hs.application
---@return boolean
function hidden_application_filter.marks_hidden(hidden, bundle_id, application)
    return HIDDEN_WINDOWS_RULES[hidden.setting].marks_hidden(hidden, bundle_id, application)
end

return hidden_application_filter
