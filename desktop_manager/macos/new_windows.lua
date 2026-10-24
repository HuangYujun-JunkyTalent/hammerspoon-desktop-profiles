local poll_until = require("desktop_manager.macos.poll_until")
local retained_timers = require("desktop_manager.macos.retained_timers")
local track_windows = require("desktop_manager.macos.track_windows")

local new_windows = {}

---The menu items that open a new window, tried in order.
---Command-N is left out, because Calendar, Mail, Notes and Slack create an event, a message or a
---note with it.
local NEW_WINDOW_MENU_ITEMS = { "New Window", "New Finder Window" }
local WINDOW_POLL_SECONDS = 0.25

---Gives the records of one switch new windows, and keeps track of the windows it gave and of the
---windows that its launches of applications opened.
---@class NewWindowSession
---@field timing Timing
---@field given_ids table<integer, boolean>
---@field launched_ids table<integer, boolean>
local NewWindowSession = {}
NewWindowSession.__index = NewWindowSession

---@param timing Timing
---@return NewWindowSession
function new_windows.start_session(timing)
    return setmetatable({ timing = timing, given_ids = {}, launched_ids = {} }, NewWindowSession)
end

---@param application table an hs.application
---@return boolean whether a menu item that opens a new window was selected
local function select_new_window_menu_item(application)
    for _, item in ipairs(NEW_WINDOW_MENU_ITEMS) do
        if application:selectMenuItem(item) then
            return true
        end
    end
    return false
end

---The window with the recorded title among the candidates, or else the first candidate.
---@param application table an hs.application
---@param is_candidate fun(window_id: integer): boolean
---@param title string
---@return table|nil an hs.window
function NewWindowSession:pick_window(application, is_candidate, title)
    local first = nil
    for _, window in ipairs(application:allWindows()) do
        local window_id = window:id()
        if
            window_id
            and window_id > 0
            and not self.given_ids[window_id]
            and is_candidate(window_id)
        then
            if (window:title() or "") == title then
                return window
            end
            first = first or window
        end
    end
    return first
end

---@param window table an hs.window
---@param on_done fun(window: table|nil, error_message: string|nil)
function NewWindowSession:give_window(window, on_done)
    self.given_ids[window:id()] = true
    self.launched_ids[window:id()] = nil
    retained_timers.after(self.timing.window_settle_seconds, function()
        on_done(window, nil)
    end)
end

---Polls for a window of the application of the record that `is_new` accepts, up to
---`application_launch_timeout_seconds`, and calls `on_found` with the window, or `on_done` with
---the failure.
---@param record WindowRecord
---@param is_new fun(window_id: integer): boolean
---@param action string the words that name what should have opened the window
---@param on_found fun(window: table)
---@param on_done fun(window: table|nil, error_message: string|nil)
function NewWindowSession:poll_for_window(record, is_new, action, on_found, on_done)
    poll_until.wait_for_value(
        function()
            local application = hs.application.get(record.bundle_id)
            return application and self:pick_window(application, is_new, record.title)
        end,
        self.timing.application_launch_timeout_seconds,
        WINDOW_POLL_SECONDS,
        function(window)
            if not window then
                on_done(
                    nil,
                    string.format("%s opened no new window after %s", record.app_name, action)
                )
                return
            end
            on_found(window)
        end
    )
end

---Waits for a window after the launch of the application of the record, and notes every window
---that the launch opened, so that the later records of the session take them.
---@param record WindowRecord
---@param on_done fun(window: table|nil, error_message: string|nil)
function NewWindowSession:wait_for_launched_window(record, on_done)
    self:poll_for_window(
        record,
        function()
            return true
        end,
        "a launch",
        function(window)
            local application = hs.application.get(record.bundle_id)
            for window_id in pairs(track_windows.index_ids(application:allWindows())) do
                self.launched_ids[window_id] = true
            end
            self:give_window(window, on_done)
        end,
        on_done
    )
end

---Waits for a window that `is_new` accepts after the action.
---@param record WindowRecord
---@param is_new fun(window_id: integer): boolean
---@param action string the words that name what should have opened the window
---@param on_done fun(window: table|nil, error_message: string|nil)
function NewWindowSession:wait_for_new_window(record, is_new, action, on_done)
    self:poll_for_window(record, is_new, action, function(window)
        self:give_window(window, on_done)
    end, on_done)
end

---Gets a window that did not exist before, for a record whose window no longer exists.
---The window is one that a launch in this session opened and no record took, or else one that the
---menu item for a new window opens, or else the main window that a reopen of the application
---shows, as a click on its icon in the Dock does.
---A window opens on the desktop that shows, and the restore moves it to its recorded desktop by its
---frame and its id.
---@param record WindowRecord
---@param on_done fun(window: table|nil, error_message: string|nil)
function NewWindowSession:provide_window(record, on_done)
    local application = hs.application.get(record.bundle_id)
    if not application then
        hs.application.open(record.bundle_id)
        self:wait_for_launched_window(record, on_done)
        return
    end
    local launched_window = self:pick_window(application, function(window_id)
        return self.launched_ids[window_id] == true
    end, record.title)
    if launched_window then
        self:give_window(launched_window, on_done)
        return
    end
    local existing_ids = track_windows.index_ids(application:allWindows())
    local function is_new(window_id)
        return not existing_ids[window_id]
    end
    if select_new_window_menu_item(application) then
        self:wait_for_new_window(record, is_new, "its menu item for a new window", on_done)
        return
    end
    hs.application.launchOrFocusByBundleID(record.bundle_id)
    self:wait_for_new_window(record, is_new, "a reopen", on_done)
end

return new_windows
