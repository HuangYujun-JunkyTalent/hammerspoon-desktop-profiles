local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local window_inventory = require("desktop_manager.macos.window_inventory")

---Long enough for three runs of the script and their waits for late output.
local REFRESH_SECONDS = 5

---A world whose controller has ended its own refreshes, with a window that only the list of the
---window server shows.
---@return table world
---@return table reading the window out of reach
---@return fun(): table<integer, boolean> list_known_window_ids the windows of the window filter
local function start_world_with_unseen_window()
    local world, controller = controller_world.start_world()
    local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
    world.advance(controller_world.SETTLE_SECONDS)
    return world, reading, function()
        return controller:list_filter_window_ids()
    end
end

---@param inventory WindowInventory
---@return integer[] the ids of the windows of the inventory
local function list_inventory_ids(inventory)
    local window_ids = {}
    for _, window in ipairs(inventory.windows) do
        table.insert(window_ids, window.window_id)
    end
    return window_ids
end

---@param world table
---@param inventory WindowInventory
---@param list_known_window_ids fun(): table<integer, boolean>
---@return integer calls of `on_done`
---@return integer runs of the script
local function refresh_and_count(world, inventory, list_known_window_ids)
    local calls, runs_before = 0, world.server_list_run_count
    window_inventory.refresh(inventory, list_known_window_ids, function()
        calls = calls + 1
    end)
    world.advance(REFRESH_SECONDS)
    return calls, world.server_list_run_count - runs_before
end

return {
    a_list_that_comes_after_the_exit_reaches_the_inventory_from_one_run = function()
        local world, reading, list_known_window_ids = start_world_with_unseen_window()
        world.is_server_list_after_exit = true
        local inventory = window_inventory.new()
        local calls, runs = refresh_and_count(world, inventory, list_known_window_ids)
        expect.equal(calls, 1)
        expect.equal(runs, 1)
        expect.equal(list_inventory_ids(inventory), { reading.id })
    end,

    an_empty_list_runs_the_script_again_before_the_waiting_call = function()
        local world, reading, list_known_window_ids = start_world_with_unseen_window()
        world.empty_server_list_count = 2
        local inventory = window_inventory.new()
        local calls, runs = refresh_and_count(world, inventory, list_known_window_ids)
        expect.equal(calls, 1)
        expect.equal(runs, 3)
        expect.equal(list_inventory_ids(inventory), { reading.id })
    end,

    three_empty_lists_keep_the_windows_of_the_last_refresh = function()
        local world, reading, list_known_window_ids = start_world_with_unseen_window()
        local inventory = window_inventory.new()
        refresh_and_count(world, inventory, list_known_window_ids)
        world.empty_server_list_count = 5
        local calls, runs = refresh_and_count(world, inventory, list_known_window_ids)
        expect.equal(calls, 1)
        expect.equal(runs, 3)
        expect.equal(list_inventory_ids(inventory), { reading.id })
        expect.equal(inventory.is_refreshing, false)
        expect.equal(world.empty_server_list_count, 2)
    end,

    the_run_after_an_empty_list_serves_the_calls_that_wait_for_a_later_list = function()
        local world, reading, list_known_window_ids = start_world_with_unseen_window()
        world.empty_server_list_count = 1
        local inventory = window_inventory.new()
        local runs_before, calls = world.server_list_run_count, {}
        window_inventory.refresh(inventory, list_known_window_ids, function()
            table.insert(calls, "first sees " .. #inventory.windows)
        end)
        window_inventory.refresh_from_now(inventory, list_known_window_ids, function()
            table.insert(calls, "later sees " .. #inventory.windows)
        end)
        world.advance(REFRESH_SECONDS)
        expect.equal(calls, { "first sees 1", "later sees 1" })
        expect.equal(world.server_list_run_count - runs_before, 2)
        expect.equal(list_inventory_ids(inventory), { reading.id })
    end,
}
