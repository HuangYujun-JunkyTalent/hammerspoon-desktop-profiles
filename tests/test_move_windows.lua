local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local fake_worlds = require("tests.fake_worlds")
local move_windows = require("desktop_manager.macos.move_windows")

local BUILTIN_SCREEN = fake_worlds.build_builtin_screen()
local DELL_SCREEN = fake_worlds.build_dell_screen()

---A world with three windows of Safari on the desktops 3, 14 and 64 of the built-in display, and a
---Dell monitor with the desktops 7 and 8.
---@return table world
local function start_world()
    local windows = {}
    for index, space_id in ipairs({ 3, 14, 64 }) do
        table.insert(windows, {
            id = 40 + index,
            bundle_id = "com.apple.Safari",
            title = "Window " .. index,
            space_id = space_id,
            frame = { x = 0, y = 25, w = 720, h = 875 },
        })
    end
    return fake_hammerspoon.install({
        screens = { BUILTIN_SCREEN, DELL_SCREEN },
        displays = fake_worlds.build_two_displays({ 3, 14, 64 }, { 7, 8 }),
        applications = { { bundle_id = "com.apple.Safari", name = "Safari", is_running = true } },
        windows = windows,
    })
end

---@param world table
---@param moves WindowMove[]
---@return MoveFailure[]|nil failures nil while the moves wait
---@return number seconds until `on_done`
local function move_and_settle(world, moves)
    local failures, finished_at = nil, nil
    local started_at = world.clock
    move_windows.move_all(moves, fake_worlds.create_default_timing(), function(result)
        failures, finished_at = result, world.clock
    end)
    world.advance(5)
    return failures, finished_at and finished_at - started_at
end

return {
    the_windows_of_a_batch_move_together = function()
        local world = start_world()
        local failures, seconds = move_and_settle(world, {
            { window_id = 41, space_id = 14 },
            { window_id = 42, space_id = 64 },
            { window_id = 43, space_id = 64 },
        })
        expect.equal(failures, {})
        expect.equal(world.window_moves, { "41 to 14", "42 to 64" })
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[42].space_id, 64)
        expect.equal(seconds < 0.5, true)
    end,

    a_window_that_stays_is_reported_and_the_others_move = function()
        local world = start_world()
        world.unmovable_window_ids[41] = true
        local failures, seconds = move_and_settle(world, {
            { window_id = 41, space_id = 14 },
            { window_id = 42, space_id = 3 },
        })
        expect.equal(failures, {
            {
                window_id = 41,
                space_id = 14,
                message = "did not reach its desktop within 1 seconds",
            },
        })
        expect.equal(world.windows[42].space_id, 3)
        expect.equal(seconds >= 1 and seconds < 1.2, true)
    end,

    a_window_slower_than_its_deadline_is_reported = function()
        local world = start_world()
        world.move_delay_seconds = 1.5
        local failures = move_and_settle(world, { { window_id = 41, space_id = 14 } })
        expect.equal(#failures, 1)
        expect.equal(world.windows[41].space_id, 14)
    end,

    each_window_of_a_batch_waits_from_its_own_call = function()
        local world = start_world()
        world.move_call_seconds = 0.6
        world.move_delay_seconds = 0.5
        local failures = move_and_settle(world, {
            { window_id = 41, space_id = 14 },
            { window_id = 42, space_id = 64 },
        })
        expect.equal(failures, {})
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[42].space_id, 64)
    end,

    a_move_that_hammerspoon_refuses_is_reported_at_once = function()
        local world = start_world()
        local failures = move_and_settle(world, {
            { window_id = 41, space_id = 8 },
            { window_id = 42, space_id = 3 },
        })
        expect.equal(#failures, 1)
        expect.equal(failures[1].window_id, 41)
        expect.equal(
            failures[1].message:match("^Hammerspoon refused the move: .*another display") ~= nil,
            true
        )
        expect.equal(world.windows[41].space_id, 3)
        expect.equal(world.windows[42].space_id, 3)
    end,
}
