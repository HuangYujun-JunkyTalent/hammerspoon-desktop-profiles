local app_pool = require("desktop_manager.core.app_pool")
local track_windows = require("desktop_manager.macos.track_windows")
local window_inventory = require("desktop_manager.macos.window_inventory")

local list_known_windows = {}

---The windows that Hammerspoon knows: the windows of the window filter, the windows that a reach
---moved into view until the filter lists them, and the windows of `hs.window.allWindows` that a
---caller asks for by their ids.
---@class KnownWindows
---@field window_filter table an hs.window.filter
---@field window_inventory WindowInventory the windows that accessibility does not reach
---@field read_app_pool fun(): AppPool
---@field reached_windows table<integer, table> the hs.window of each window that a reach moved into
---view, until the window filter lists it
local KnownWindows = {}
KnownWindows.__index = KnownWindows

---@param window_filter table an hs.window.filter
---@param inventory WindowInventory
---@param read_app_pool fun(): AppPool the managed applications at the time of each call
---@return KnownWindows
function list_known_windows.new(window_filter, inventory, read_app_pool)
    return setmetatable({
        window_filter = window_filter,
        window_inventory = inventory,
        read_app_pool = read_app_pool,
        reached_windows = {},
    }, KnownWindows)
end

---Some windows of macOS report the window id 0, such as one of Control Center.
---@param window table an hs.window
---@return boolean
local function has_valid_id(window)
    local window_id = window:id()
    return window_id ~= nil and window_id > 0
end

---@param window_filter table an hs.window.filter
---@return table[] the hs.window objects of the filter that have a valid id
local function list_filter_windows(window_filter)
    local windows = {}
    for _, window in ipairs(window_filter:getWindows()) do
        if has_valid_id(window) then
            table.insert(windows, window)
        end
    end
    return windows
end

---@param reached_windows table<integer, table>
---@param listed table<integer, table> the hs.window of each window id that the filter lists
---@return table[] joined the reached windows that the filter does not list and that keep their
---ids, by ascending id
---@return integer[] dropped_ids the reached windows that the filter lists or whose id changed
local function join_reached_windows(reached_windows, listed)
    local reached_ids = {}
    for window_id in pairs(reached_windows) do
        table.insert(reached_ids, window_id)
    end
    table.sort(reached_ids)
    local joined, dropped_ids = {}, {}
    for _, window_id in ipairs(reached_ids) do
        local window = reached_windows[window_id]
        if not listed[window_id] and window:id() == window_id then
            table.insert(joined, window)
        else
            table.insert(dropped_ids, window_id)
        end
    end
    return joined, dropped_ids
end

---@param window_ids integer[]
---@param listed table<integer, table> the hs.window of each window id that is known already
---@return table[] the hs.window objects of `hs.window.allWindows` among `window_ids` that `listed`
---lacks, in the order of `hs.window.allWindows`
local function find_unlisted_windows(window_ids, listed)
    local missing = {}
    for _, window_id in ipairs(window_ids) do
        if not listed[window_id] then
            missing[window_id] = true
        end
    end
    if next(missing) == nil then
        return {}
    end
    local found = {}
    for _, window in ipairs(hs.window.allWindows()) do
        local window_id = window:id()
        if window_id and missing[window_id] then
            missing[window_id] = nil
            table.insert(found, window)
        end
    end
    return found
end

---The windows of the window filter, and the windows of `window_ids` that the filter does not list.
---The filter drops a window whose subrole is not AXStandardWindow when the window hides or
---minimizes, as the window of Calendar does while Calendar is hidden.
---@param window_ids integer[]
---@return table[] hs.window objects
function KnownWindows:list_all(window_ids)
    local windows = list_filter_windows(self.window_filter)
    local listed = track_windows.index_by_id(windows)
    local joined, dropped_ids = join_reached_windows(self.reached_windows, listed)
    for _, window_id in ipairs(dropped_ids) do
        self.reached_windows[window_id] = nil
    end
    for window_id, window in pairs(self.reached_windows) do
        listed[window_id] = window
    end
    for _, window in ipairs(joined) do
        table.insert(windows, window)
    end
    for _, window in ipairs(find_unlisted_windows(window_ids, listed)) do
        table.insert(windows, window)
    end
    return windows
end

---The windows of the managed applications that the tool knows.
---@param window_ids integer[]
---@return table[] hs.window objects
function KnownWindows:list_managed(window_ids)
    local windows = self:list_all(window_ids)
    return app_pool.keep_managed_by(self.read_app_pool(), windows, function(window)
        return track_windows.bundle_id_of(window:application())
    end)
end

---The windows of the managed applications that the window server listed on a desktop out of view
---at the last refresh of the inventory, and that Hammerspoon has not seen.
---@param managed_windows table[] hs.window objects
---@return ServerWindow[]
function KnownWindows:list_unreached_managed(managed_windows)
    return app_pool.keep_managed(
        self.read_app_pool(),
        window_inventory.list_unreached_windows(
            self.window_inventory,
            track_windows.index_ids(managed_windows)
        )
    )
end

---@param window_id integer
---@return table|nil an hs.window
function KnownWindows:find(window_id)
    for _, window in ipairs(self.window_filter:getWindows()) do
        if window:id() == window_id then
            return window
        end
    end
    return hs.window.get(window_id)
end

---Keeps a window that a reach moved into view, until the window filter lists it.
---@param window_id integer
---@param window table an hs.window
function KnownWindows:remember_reached(window_id, window)
    self.reached_windows[window_id] = window
end

return list_known_windows
