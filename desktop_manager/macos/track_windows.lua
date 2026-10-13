local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")

local track_windows = {}

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

return track_windows
