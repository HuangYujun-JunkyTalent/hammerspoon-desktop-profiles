local javascript_tasks = require("desktop_manager.macos.javascript_tasks")
local read_desktops = require("desktop_manager.macos.read_desktops")
local retained_timers = require("desktop_manager.macos.retained_timers")
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
---application with windows of its own at the last refresh, with a Dock icon or without one, which
---may keep the desktop from a removal
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
---@return table<integer, ServerApplication> dock_application_by_pid the applications with a Dock
---icon among the processes
---@return table<integer, ServerApplication> application_by_pid the applications with windows of
---their own among the processes, with a Dock icon or without one, as the agents of the menu bar
local function map_applications(pids)
    local dock_application_by_pid, application_by_pid = {}, {}
    for _, pid in ipairs(pids) do
        local application = hs.application.applicationForPID(pid)
        if application and track_windows.may_own_windows(application) then
            local bundle_id, app_name = track_windows.identify_application(application)
            application_by_pid[pid] = { bundle_id = bundle_id, app_name = app_name }
            if application:kind() == track_windows.REGULAR_APPLICATION_KIND then
                dock_application_by_pid[pid] = application_by_pid[pid]
            end
        end
    end
    return dock_application_by_pid, application_by_pid
end

---How long a run waits after its exit for the rest of its output, because Hammerspoon may give
---the output of a task through the streaming callback after the exit callback.
local LATE_OUTPUT_SECONDS = 0.3
---The runs of the script for one refresh, the first included, before the refresh keeps the
---windows of the last one.
local MAX_RUNS = 3

---@param output string
---@return table[]|nil rows the list of the output, or nil when the output holds no whole list
local function decode_rows(output)
    -- osascript ends the result with a newline, so an output without one is empty or cut short,
    -- and the decoder, which logs an error on such an output, does not run.
    if output:sub(-1) ~= "\n" then
        return nil
    end
    local is_decoded, rows = pcall(hs.json.decode, output)
    if is_decoded and type(rows) == "table" then
        return rows
    end
    return nil
end

---@param inventory WindowInventory
---@param rows table[]
---@param list_known_window_ids fun(): table<integer, boolean>
local function take_rows(inventory, rows, list_known_window_ids)
    local hidden_space_lists = map_hidden_space_lists()
    local hidden_spaces = pick_last_spaces(hidden_space_lists)
    -- The window filter follows no application without a Dock icon that the profiles do not name,
    -- so the windows of such an application keep their desktops through this list alone.
    local dock_application_by_pid, application_by_pid =
        map_applications(server_windows.list_owner_pids(rows, hidden_spaces))
    inventory.windows = server_windows.select_unreached_windows(
        rows,
        hidden_spaces,
        dock_application_by_pid,
        list_known_window_ids()
    )
    inventory.occupying_windows =
        server_windows.map_occupying_windows(rows, hidden_space_lists, application_by_pid)
end

---@param callbacks fun()[]
local function call_all(callbacks)
    for _, callback in ipairs(callbacks) do
        callback()
    end
end

local start_run

---Ends the refresh, calls the calls that waited for it, and starts the next refresh when calls
---wait for one.
---@param inventory WindowInventory
---@param list_known_window_ids fun(): table<integer, boolean>
---@param taken_at number when the refresh began to take its list or gave up, in seconds since the
---epoch
local function finish_refresh(inventory, list_known_window_ids, taken_at)
    inventory.last_update_started_at = taken_at
    inventory.is_refreshing = false
    local finished = inventory.waiting
    inventory.waiting, inventory.next_waiting = inventory.next_waiting, {}
    call_all(finished)
    if #inventory.waiting > 0 and not inventory.is_refreshing then
        inventory.is_refreshing = true
        start_run(inventory, list_known_window_ids, 1)
    end
end

---Ends the refresh when the script cannot start, together with the calls that wait for a later
---refresh, because that one could not start either.
---@param inventory WindowInventory
local function give_up_refresh(inventory)
    inventory.last_update_started_at = hs.timer.secondsSinceEpoch()
    inventory.is_refreshing = false
    local finished = inventory.waiting
    for _, callback in ipairs(inventory.next_waiting) do
        table.insert(finished, callback)
    end
    inventory.waiting, inventory.next_waiting = {}, {}
    call_all(finished)
end

---Runs the script once for the refresh that runs, and again when the run gives no whole list.
---The task collects the output through a streaming callback, because a list above 64 KiB blocks a
---task without one, as `javascript_tasks.new` says.
---@param inventory WindowInventory
---@param list_known_window_ids fun(): table<integer, boolean>
---@param run_number integer
function start_run(inventory, list_known_window_ids, run_number)
    local chunks = {}
    local exit_code, late_output_timer
    local is_over = false
    ---@param is_last_chance boolean whether no more output may come
    local function try_to_end(is_last_chance)
        if is_over or not exit_code then
            return
        end
        -- The time leaves out the wait for late output, during which Hammerspoon is free, so that
        -- the log of the search measures the time that the list held Hammerspoon.
        local tried_at = hs.timer.secondsSinceEpoch()
        local rows = exit_code == 0 and decode_rows(table.concat(chunks)) or nil
        if not rows and not is_last_chance then
            return
        end
        is_over = true
        retained_timers.stop(late_output_timer)
        if rows then
            take_rows(inventory, rows, list_known_window_ids)
        elseif run_number < MAX_RUNS then
            -- The next run starts after the calls that wait for a later refresh, so it serves them.
            for _, callback in ipairs(inventory.next_waiting) do
                table.insert(inventory.waiting, callback)
            end
            inventory.next_waiting = {}
            start_run(inventory, list_known_window_ids, run_number + 1)
            return
        end
        finish_refresh(inventory, list_known_window_ids, tried_at)
    end
    local task = javascript_tasks.new("list_server_windows.js", {}, function(code, stdout)
        exit_code = code
        table.insert(chunks, stdout or "")
        try_to_end(code ~= 0)
        if not is_over then
            late_output_timer = retained_timers.after(LATE_OUTPUT_SECONDS, function()
                try_to_end(true)
            end)
        end
    end, function(_, stdout)
        table.insert(chunks, stdout or "")
        try_to_end(false)
        return true
    end)
    if not task or not task:start() then
        give_up_refresh(inventory)
    end
end

---Lists the windows of the window server again, and calls `on_done` when the list is new.
---A refresh that runs already takes the call, so the script runs once at a time.
---A script that gives no list runs again, up to three runs, and then the refresh keeps the windows
---of the last one.
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
    inventory.is_refreshing = true
    start_run(inventory, list_known_window_ids, 1)
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
