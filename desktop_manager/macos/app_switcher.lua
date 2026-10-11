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
function app_switcher.list_windows(bundle_id, filter_windows)
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

---The application of the number for the list, with its windows in the order of the window ids.
---The first press selects the window after the focused one when the application is in front, and
---otherwise the window of the application that had the focus last.
---@param entry AppNumber
---@param filter_windows table[] the hs.window objects of the window filter
---@param screen_uuid_by_space table<integer, string> the display of each desktop
---@return SwitchApplication
---@return table<integer, table> the hs.window of each window id
function app_switcher.describe_application(entry, filter_windows, screen_uuid_by_space)
    local windows = app_switcher.list_windows(entry.bundle_id, filter_windows)
    local window_by_id, window_ids = {}, {}
    for _, window in ipairs(windows) do
        window_by_id[window:id()] = window
        table.insert(window_ids, window:id())
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
        table.insert(switch_windows, {
            window_id = window_id,
            title = window_by_id[window_id]:title() or "",
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
    },
        window_by_id
end

---Shows the desktop of the window when another desktop shows, then unhides its application,
---unminimizes it and focuses it.
---@param window table an hs.window
---@param timing Timing
---@param on_done fun(error_message: string|nil)
function app_switcher.bring_to_front(window, timing, on_done)
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

---Brings the selected window of the application of the number to the front.
---Without a selected window, a recorded window on a desktop that Hammerspoon has not seen is
---reached by showing that desktop, and an application without such a window gets a new window.
---@param entry AppNumber
---@param window table|nil the selected hs.window
---@param recorded_window_ids integer[] the windows of the application that some profile recorded
---@param timing Timing
---@param on_done fun(error_message: string|nil)
function app_switcher.switch_to_selection(entry, window, recorded_window_ids, timing, on_done)
    if window then
        app_switcher.bring_to_front(window, timing, on_done)
        return
    end
    for _, window_id in ipairs(recorded_window_ids) do
        local space_id = read_desktops.find_window_space_id(window_id)
        if space_id then
            switch_desktops.switch_to_space(space_id, timing, function(error_message)
                local reached = app_switcher.list_windows(entry.bundle_id, {})
                if error_message or #reached == 0 then
                    open_new_window(entry, timing, on_done)
                    return
                end
                app_switcher.bring_to_front(reached[1], timing, on_done)
            end)
            return
        end
    end
    open_new_window(entry, timing, on_done)
end

return app_switcher
