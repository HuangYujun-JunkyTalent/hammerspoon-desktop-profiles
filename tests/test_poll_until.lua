local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local fake_worlds = require("tests.fake_worlds")
local poll_until = require("desktop_manager.macos.poll_until")

---@return table world
local function start_world()
    return fake_hammerspoon.install({
        screens = { fake_worlds.build_builtin_screen() },
        displays = { { uuid = "BUILTIN-UUID", space_ids = { 3 }, active_space_id = 3 } },
        applications = {},
        windows = {},
    })
end

---Waits 1 second in checks of 0.2 seconds for a condition that turns true `true_after` seconds
---from now, while a block of Hammerspoon of `block_seconds` starts after 0.1 seconds.
---@param true_after number
---@param block_seconds number
---@return boolean|nil result the result of the wait, or nil while it runs
---@return number seconds from the start to the result
local function wait_through_block(true_after, block_seconds)
    local world = start_world()
    local started_at, result, ended_at = world.clock, nil, nil
    if block_seconds > 0 then
        world.schedule(0.1, function()
            world.clock = world.clock + block_seconds
        end)
    end
    poll_until.wait(
        function()
            return world.clock - started_at >= true_after
        end,
        1,
        0.2,
        function(is_met)
            result, ended_at = is_met, world.clock
        end
    )
    world.advance(10)
    return result, (ended_at or world.clock) - started_at
end

return {
    a_wait_without_a_block_ends_at_its_timeout = function()
        local result, seconds = wait_through_block(5, 0)
        expect.equal(result, false)
        expect.equal(seconds >= 1 and seconds < 1.3, true)
    end,

    a_block_of_hammerspoon_does_not_take_the_time_of_the_wait = function()
        local result, seconds = wait_through_block(3.5, 3)
        expect.equal(result, true)
        expect.equal(seconds >= 3.5 and seconds < 3.8, true)
    end,

    a_wait_through_a_block_still_ends_after_its_checks = function()
        local result, seconds = wait_through_block(20, 3)
        expect.equal(result, false)
        expect.equal(seconds >= 3.9 and seconds < 4.3, true)
    end,
}
