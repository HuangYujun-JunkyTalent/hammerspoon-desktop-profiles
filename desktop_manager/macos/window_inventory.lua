local read_desktops = require("desktop_manager.macos.read_desktops")
local server_windows = require("desktop_manager.core.server_windows")
local track_windows = require("desktop_manager.macos.track_windows")

---Keeps the windows that accessibility does not reach, from the list of the window server that
---`list_server_windows.js` prints.
---A refresh runs the script in the background in about 0.2 seconds, so the lists use the windows
---of the last refresh and draw again when a refresh ends.
local window_inventory = {}

local OSASCRIPT_PATH = "/usr/bin/osascript"
local SCRIPT_PATH = (
    debug.getinfo(1, "S").source:match("^@(.*/desktop_manager/macos)/window_inventory%.lua$")
    or "./desktop_manager/macos"
) .. "/list_server_windows.js"

---The kind of an hs.application with a Dock icon.
local REGULAR_APPLICATION_KIND = 1

---@class WindowInventory
---@field windows ServerWindow[] the windows out of reach at the last refresh
---@field occupied_space_ids table<integer, boolean> the desktops out of view that held a window of
---an application with a Dock icon at the last refresh
---@field is_refreshing boolean
---@field waiting fun()[] the calls that wait for the refresh that runs
---@field next_waiting fun()[] the calls that wait for a refresh that starts after the one that runs

---@return WindowInventory
function window_inventory.new()
    return {
        windows = {},
        occupied_space_ids = {},
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
        if application and application:kind() == REGULAR_APPLICATION_KIND then
            application_by_pid[pid] = {
                bundle_id = track_windows.bundle_id_of(application),
                app_name = application:name() or "unknown",
            }
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
---@param inventory WindowInventory
---@param list_known_window_ids fun(): table<integer, boolean>
local function start_refresh(inventory, list_known_window_ids)
    inventory.is_refreshing = true
    local task = hs.task.new(OSASCRIPT_PATH, function(exit_code, stdout)
        inventory.is_refreshing = false
        local is_decoded, rows = pcall(hs.json.decode, stdout or "")
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
            inventory.occupied_space_ids =
                server_windows.find_occupied_space_ids(rows, hidden_space_lists, application_by_pid)
        end
        local finished = inventory.waiting
        inventory.waiting, inventory.next_waiting = inventory.next_waiting, {}
        call_all(finished)
        if #inventory.waiting > 0 and not inventory.is_refreshing then
            start_refresh(inventory, list_known_window_ids)
        end
    end, { "-l", "JavaScript", SCRIPT_PATH })
    if not task or not task:start() then
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
