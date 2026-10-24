local javascript_tasks = require("desktop_manager.macos.javascript_tasks")
local read_desktops = require("desktop_manager.macos.read_desktops")
local server_windows = require("desktop_manager.core.server_windows")
local track_windows = require("desktop_manager.macos.track_windows")

---Keeps the windows that accessibility does not reach, from the list of the window server that
---`list_server_windows.js` prints.
---A refresh runs the script in the background in about 0.2 seconds, so the lists use the windows
---of the last refresh and draw again when a refresh ends.
local window_inventory = {}

---@class WindowInventory
---@field windows ServerWindow[] the windows out of reach at the last refresh
---@field occupying_windows table<integer, integer> the desktop out of view of each window of an
---application with a Dock icon at the last refresh, which may keep the desktop from a removal
---@field is_refreshing boolean
---@field waiting fun()[] the calls that wait for the refresh that runs
---@field next_waiting fun()[] the calls that wait for a refresh that starts after the one that runs
---@field last_update_started_at number|nil when the last refresh began to take its list, before
---the calls that waited for it, in seconds since the epoch

---@return WindowInventory
function window_inventory.new()
    return {
        windows = {},
        occupying_windows = {},
        is_refreshing = false,
        waiting = {},
        next_waiting = {},
    }
end

---@return table<integer, integer[]> the desktops out of view that macOS lists for each window
local function map_hidden_space_lists()
    local space_ids_by_window_id = {}
    for _, screen in ipairs(read_desktops.read_desktop_layout().screens) do
        for _, space_id in ipairs(screen.space_ids) do
            if space_id ~= screen.active_space_id then
                for _, window_id in ipairs(hs.spaces.windowsForSpace(space_id) or {}) do
                    space_ids_by_window_id[window_id] = space_ids_by_window_id[window_id] or {}
                    table.insert(space_ids_by_window_id[window_id], space_id)
                end
            end
        end
    end
    return space_ids_by_window_id
end

---@param space_ids_by_window_id table<integer, integer[]>
---@return table<integer, integer> the last desktop out of view that macOS lists for each window
local function pick_last_spaces(space_ids_by_window_id)
    local space_by_window_id = {}
    for window_id, space_ids in pairs(space_ids_by_window_id) do
        space_by_window_id[window_id] = space_ids[#space_ids]
    end
    return space_by_window_id
end

---@return table<integer, integer> the desktop of each window on a desktop out of view
local function map_hidden_spaces()
    return pick_last_spaces(map_hidden_space_lists())
end

---@param pids integer[]
---@return table<integer, ServerApplication> the applications with a Dock icon among the processes
local function map_applications(pids)
    local application_by_pid = {}
    for _, pid in ipairs(pids) do
        local application = hs.application.applicationForPID(pid)
        if application and application:kind() == track_windows.REGULAR_APPLICATION_KIND then
            local bundle_id, app_name = track_windows.identify_application(application)
            application_by_pid[pid] = { bundle_id = bundle_id, app_name = app_name }
        end
    end
    return application_by_pid
end

---@param callbacks fun()[]
local function call_all(callbacks)
    for _, callback in ipairs(callbacks) do
        callback()
    end
end

---Runs the script once, and then once more when calls wait for a list that starts later.
---The task collects the output through a streaming callback, because a list above 64 KiB blocks a
---task without one, as `javascript_tasks.new` says.
---@param inventory WindowInventory
---@param list_known_window_ids fun(): table<integer, boolean>
local function start_refresh(inventory, list_known_window_ids)
    inventory.is_refreshing = true
    local chunks = {}
    local task = javascript_tasks.new("list_server_windows.js", {}, function(exit_code, stdout)
        inventory.last_update_started_at = hs.timer.secondsSinceEpoch()
        inventory.is_refreshing = false
        table.insert(chunks, stdout or "")
        local is_decoded, rows = pcall(hs.json.decode, table.concat(chunks))
        if exit_code == 0 and is_decoded and type(rows) == "table" then
            local hidden_space_lists = map_hidden_space_lists()
            local hidden_spaces = pick_last_spaces(hidden_space_lists)
            local application_by_pid =
                map_applications(server_windows.list_owner_pids(rows, hidden_spaces))
            inventory.windows = server_windows.select_unreached_windows(
                rows,
                hidden_spaces,
                application_by_pid,
                list_known_window_ids()
            )
            inventory.occupying_windows =
                server_windows.map_occupying_windows(rows, hidden_space_lists, application_by_pid)
        end
        local finished = inventory.waiting
        inventory.waiting, inventory.next_waiting = inventory.next_waiting, {}
        call_all(finished)
        if #inventory.waiting > 0 and not inventory.is_refreshing then
            start_refresh(inventory, list_known_window_ids)
        end
    end, function(_, stdout)
        table.insert(chunks, stdout or "")
        return true
    end)
    if not task or not task:start() then
        inventory.last_update_started_at = hs.timer.secondsSinceEpoch()
        inventory.is_refreshing = false
        local finished = inventory.waiting
        for _, callback in ipairs(inventory.next_waiting) do
            table.insert(finished, callback)
        end
        inventory.waiting, inventory.next_waiting = {}, {}
        call_all(finished)
    end
end

---Lists the windows of the window server again, and calls `on_done` when the list is new.
---A refresh that runs already takes the call, so the script runs once at a time.
---A script that fails keeps the windows of the last refresh.
---@param inventory WindowInventory
---@param list_known_window_ids fun(): table<integer, boolean> the windows that accessibility
---reaches when the script ends
---@param on_done fun()|nil
function window_inventory.refresh(inventory, list_known_window_ids, on_done)
    if on_done then
        table.insert(inventory.waiting, on_done)
    end
    if inventory.is_refreshing then
        return
    end
    start_refresh(inventory, list_known_window_ids)
end

---Lists the windows of the window server again, and calls `on_done` with a list that started after
---the call, such as after the tool moved windows.
---@param inventory WindowInventory
---@param list_known_window_ids fun(): table<integer, boolean>
---@param on_done fun()
function window_inventory.refresh_from_now(inventory, list_known_window_ids, on_done)
    if inventory.is_refreshing then
        table.insert(inventory.next_waiting, on_done)
        return
    end
    window_inventory.refresh(inventory, list_known_window_ids, on_done)
end

---The windows of the last refresh that are still on a desktop out of view and out of reach.
---@param inventory WindowInventory
---@param known_window_ids table<integer, boolean>
---@return ServerWindow[]
function window_inventory.list_unreached_windows(inventory, known_window_ids)
    if #inventory.windows == 0 then
        return {}
    end
    return server_windows.keep_unreached_windows(
        inventory.windows,
        map_hidden_spaces(),
        known_window_ids
    )
end

return window_inventory
