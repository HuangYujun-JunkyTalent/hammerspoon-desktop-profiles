local app_numbers = require("desktop_manager.core.app_numbers")
local new_windows = require("desktop_manager.macos.new_windows")
local read_desktops = require("desktop_manager.macos.read_desktops")
local switch_desktops = require("desktop_manager.macos.switch_desktops")
local track_windows = require("desktop_manager.macos.track_windows")

local app_switcher = {}

---Every standard window of the application that Hammerspoon knows, on any desktop.
---The windows of the window filter come first, the most recently focused one at the front.
---@param bundle_id string
---@param filter_windows table[] the hs.window objects of the window filter
---@return table[] hs.window objects
local function list_windows_of_application(bundle_id, filter_windows)
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
    local application = hs.application.get(bundle_id)
    for _, window in ipairs(application and application:allWindows() or {}) do
        if window:isStandard() then
            add(window)
        end
    end
    return windows
end

---The window after the focused one when the application is in front, and otherwise the window of
---the application that had the focus last.
---@param bundle_id string
---@param windows table[] hs.window objects, the most recently focused first
---@return table an hs.window
local function pick_window(bundle_id, windows)
    local frontmost = hs.application.frontmostApplication()
    local focused = hs.window.focusedWindow()
    if not frontmost or not focused or track_windows.bundle_id_of(frontmost) ~= bundle_id then
        return windows[1]
    end
    local window_by_id, window_ids = {}, {}
    for _, window in ipairs(windows) do
        window_by_id[window:id()] = window
        table.insert(window_ids, window:id())
    end
    return window_by_id[app_numbers.find_next_window_id(window_ids, focused:id())]
end

---Shows the desktop of the window when another desktop shows, then unhides its application,
---unminimizes it and focuses it.
---@param window table an hs.window
---@param timing Timing
---@param on_done fun(error_message: string|nil)
local function bring_to_front(window, timing, on_done)
    local function focus()
        local application = window:application()
        if application and application:isHidden() then
            application:unhide()
        end
        if window:isMinimized() then
            window:unminimize()
        end
        window:focus()
        on_done(nil)
    end
    local space_id = read_desktops.find_window_space_id(window:id())
    if space_id and not read_desktops.is_space_active(space_id) then
        switch_desktops.switch_to_space(space_id, timing, function(error_message)
            if error_message then
                on_done(error_message)
                return
            end
            focus()
        end)
        return
    end
    focus()
end

---@param entry AppNumber
---@param timing Timing
---@param on_done fun(error_message: string|nil)
local function open_new_window(entry, timing, on_done)
    local record = { bundle_id = entry.bundle_id, app_name = entry.app_name, title = "" }
    new_windows.start_session(timing):provide_window(record, function(window, error_message)
        if not window then
            on_done(error_message)
            return
        end
        window:focus()
        on_done(nil)
    end)
end

---Brings a window of the application of the number to the front.
---The windows are all the windows of the application, also those that the active profile did not
---record.
---A recorded window on a desktop that Hammerspoon has not seen is reached by showing that desktop.
---An application without a window gets a new window.
---@param entry AppNumber
---@param filter_windows table[] the hs.window objects of the window filter
---@param recorded_window_ids integer[] the windows of the application that some profile recorded
---@param timing Timing
---@param on_done fun(error_message: string|nil)
function app_switcher.switch_to_application(
    entry,
    filter_windows,
    recorded_window_ids,
    timing,
    on_done
)
    local windows = list_windows_of_application(entry.bundle_id, filter_windows)
    if #windows > 0 then
        bring_to_front(pick_window(entry.bundle_id, windows), timing, on_done)
        return
    end
    for _, window_id in ipairs(recorded_window_ids) do
        local space_id = read_desktops.find_window_space_id(window_id)
        if space_id then
            switch_desktops.switch_to_space(space_id, timing, function(error_message)
                local reached = list_windows_of_application(entry.bundle_id, {})
                if error_message or #reached == 0 then
                    open_new_window(entry, timing, on_done)
                    return
                end
                bring_to_front(reached[1], timing, on_done)
            end)
            return
        end
    end
    open_new_window(entry, timing, on_done)
end

return app_switcher
