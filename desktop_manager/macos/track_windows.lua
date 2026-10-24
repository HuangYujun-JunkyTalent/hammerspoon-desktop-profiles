local poll_until = require("desktop_manager.macos.poll_until")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")

local track_windows = {}

---Each poll for the windows that accessibility does not reach yet, or for a standard window of an
---application after its unhide, asks the applications for their windows through accessibility,
---which takes a while with many windows.
local REACH_POLL_SECONDS = 0.2

---A window filter that sees the standard windows of every desktop.
---Minimized windows and the windows of hidden applications count as well.
---@return table filter an hs.window.filter
function track_windows.new_filter()
    hs.window.filter.forceRefreshOnSpaceChange = true -- luacheck: ignore 122
    return hs.window.filter.new():setDefaultFilter({ allowRoles = "AXStandardWindow" })
end

---@param application table|nil an hs.application
---@return string
function track_windows.bundle_id_of(application)
    if not application then
        return "unknown"
    end
    return application:bundleID() or application:name() or "unknown"
end

---@param windows table[] hs.window objects
---@return table<integer, table> the hs.window of each window id
function track_windows.index_by_id(windows)
    local index = {}
    for _, window in ipairs(windows) do
        local window_id = window:id()
        if window_id then
            index[window_id] = window
        end
    end
    return index
end

---@param windows table[] hs.window objects
---@return table<integer, boolean> the ids of the windows
function track_windows.index_ids(windows)
    local ids = {}
    for _, window in ipairs(windows) do
        local window_id = window:id()
        if window_id then
            ids[window_id] = true
        end
    end
    return ids
end

---@param window table an hs.window
---@return string
function track_windows.describe(window)
    local application = window:application()
    return string.format(
        "%s window %q",
        application and application:name() or "an",
        window:title() or ""
    )
end

---Reads the application of the window, its bundle id, whether the window is minimized and whether
---the application is hidden, in that order.
---@param window table an hs.window
---@return WindowState
function track_windows.read_window_state(window)
    local application = window:application()
    return {
        bundle_id = track_windows.bundle_id_of(application),
        is_minimized = window:isMinimized(),
        is_app_hidden = application ~= nil and application:isHidden(),
    }
end

---@param window table an hs.window
---@return WindowObservation
function track_windows.observe(window)
    local application = window:application()
    local window_id = window:id()
    local is_minimized = window:isMinimized()
    local is_app_hidden = application ~= nil and application:isHidden()
    return {
        window_id = window_id,
        bundle_id = track_windows.bundle_id_of(application),
        app_name = application and application:name() or "unknown",
        title = window:title() or "",
        space_id = not is_minimized and read_desktops.find_window_space_id(window_id) or nil,
        frame = not is_minimized and read_screens.to_rect(window:frame()) or nil,
        is_out_of_sight = is_minimized or is_app_hidden,
    }
end

---@param windows ServerWindow[]
---@return table<integer, table> the hs.window of each window of the owning applications that
---accessibility reaches now
local function find_reached_windows(windows)
    local bundle_ids, reached = {}, {}
    for _, window in ipairs(windows) do
        bundle_ids[window.bundle_id] = true
    end
    for bundle_id in pairs(bundle_ids) do
        for _, application in ipairs(hs.application.applicationsForBundleID(bundle_id)) do
            for _, window in ipairs(application:allWindows()) do
                local window_id = window:id()
                if window_id then
                    reached[window_id] = window
                end
            end
        end
    end
    return reached
end

---Waits until accessibility reaches every one of the windows that Hammerspoon had not seen, as
---after a move into view or a press in Mission Control, up to the time limit.
---Each poll reads the windows of the owning applications once, instead of every window of every
---application as `hs.window.get` does.
---@param windows ServerWindow[]
---@param timeout_seconds number
---@param on_done fun(reached: table<integer, table>) the hs.window of each window that
---accessibility reaches, by its id
function track_windows.wait_until_reached(windows, timeout_seconds, on_done)
    local reached = {}
    poll_until.wait(
        function()
            reached = find_reached_windows(windows)
            for _, window in ipairs(windows) do
                if not reached[window.window_id] then
                    return false
                end
            end
            return true
        end,
        timeout_seconds,
        REACH_POLL_SECONDS,
        function()
            local found = {}
            for _, window in ipairs(windows) do
                found[window.window_id] = reached[window.window_id]
            end
            on_done(found)
        end
    )
end

---@param application table an hs.application
---@return table|nil the main window of the application when it is a standard window, and otherwise
---its first standard window
local function find_standard_window(application)
    local main_window = application:mainWindow()
    if main_window and main_window:isStandard() then
        return main_window
    end
    for _, window in ipairs(application:allWindows()) do
        if window:isStandard() then
            return window
        end
    end
    return nil
end

---Polls `find` until it gives a window, up to the time limit.
---@param find fun(): table|nil
---@param timeout_seconds number
---@param on_done fun(window: table|nil) the window that `find` gave, or nil after the time limit
local function wait_until_found(find, timeout_seconds, on_done)
    local found = nil
    poll_until.wait(
        function()
            found = find()
            return found ~= nil
        end,
        timeout_seconds,
        REACH_POLL_SECONDS,
        function()
            on_done(found)
        end
    )
end

---Waits until the application shows a standard window, as after an unhide, while its windows may
---still report another subrole such as `AXDialog`, up to the time limit.
---@param application table an hs.application
---@param timeout_seconds number
---@param on_done fun(window: table|nil) the main window of the application when it is a standard
---window, and otherwise its first standard window, or nil after the time limit
function track_windows.wait_until_standard(application, timeout_seconds, on_done)
    wait_until_found(function()
        return find_standard_window(application)
    end, timeout_seconds, on_done)
end

---Waits until the window is a standard window, as after the unhide of its application, up to the
---time limit.
---@param window table an hs.window
---@param timeout_seconds number
---@param on_done fun(window: table|nil) the window, or nil after the time limit
function track_windows.wait_until_window_standard(window, timeout_seconds, on_done)
    wait_until_found(function()
        return window:isStandard() and window or nil
    end, timeout_seconds, on_done)
end

return track_windows
