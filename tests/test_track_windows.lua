local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local fake_worlds = require("tests.fake_worlds")
local track_windows = require("desktop_manager.macos.track_windows")

---A world with two windows of Safari and one of Word on the desktop 14 of the built-in display,
---which Hammerspoon has not seen.
---@return table world
local function start_world()
    local windows = {}
    local bundle_ids = { "com.apple.Safari", "com.microsoft.Word", "com.apple.Safari" }
    for index, bundle_id in ipairs(bundle_ids) do
        table.insert(windows, {
            id = 40 + index,
            bundle_id = bundle_id,
            title = "Window " .. index,
            space_id = 14,
            frame = { x = 0, y = 25, w = 720, h = 875 },
            is_unseen = true,
        })
    end
    return fake_hammerspoon.install({
        screens = { fake_worlds.build_builtin_screen() },
        displays = { { uuid = "BUILTIN-UUID", space_ids = { 3, 14 }, active_space_id = 3 } },
        applications = {
            { bundle_id = "com.apple.Safari", name = "Safari", is_running = true },
            { bundle_id = "com.microsoft.Word", name = "Microsoft Word", is_running = true },
        },
        windows = windows,
    })
end

---@param world table
---@param window_id integer
---@return ServerWindow
local function server_window_of(world, window_id)
    local window = world.windows[window_id]
    return {
        window_id = window_id,
        bundle_id = window.bundle_id,
        app_name = world.applications[window.bundle_id].name,
        title = window.title,
        space_id = window.space_id,
        frame = window.frame,
    }
end

---Lets accessibility reach the windows after the seconds, as macOS does once their desktop shows.
---@param world table
---@param window_ids integer[]
---@param seconds number
local function reach_after(world, window_ids, seconds)
    world.schedule(seconds, function()
        for _, window_id in ipairs(window_ids) do
            world.windows[window_id].is_unseen = false
        end
    end)
end

---@param world table
---@param window_ids integer[]
---@param timeout_seconds number
---@return table<integer, table> reached
---@return number seconds until the wait ended
local function wait_and_settle(world, window_ids, timeout_seconds)
    local windows = {}
    for _, window_id in ipairs(window_ids) do
        table.insert(windows, server_window_of(world, window_id))
    end
    ---@type table<integer, table>|nil, number|nil
    local reached, finished_at = nil, nil
    track_windows.wait_until_reached(windows, timeout_seconds, function(found)
        reached, finished_at = found, world.clock
    end)
    world.advance(5)
    return expect.present(reached, "the end of the wait within 5 seconds"),
        expect.present(finished_at, "the time of the end of the wait")
end

return {
    a_window_that_accessibility_reaches_later_is_found_at_the_next_poll = function()
        local world = start_world()
        reach_after(world, { 41 }, 0.5)
        local reached, seconds = wait_and_settle(world, { 41 }, 1)
        expect.present(reached[41], "window 41 among the reached windows")
        expect.equal(math.abs(seconds - 0.6) < 0.01, true)
    end,

    a_window_that_stays_out_of_reach_is_missing_after_the_time_limit = function()
        local world = start_world()
        local reached, seconds = wait_and_settle(world, { 41 }, 1)
        expect.equal(reached[41], nil)
        expect.equal(seconds >= 1 and seconds < 1.2, true)
    end,

    each_poll_reads_the_windows_of_each_owning_application_once = function()
        local world = start_world()
        reach_after(world, { 41, 42, 43 }, 0.5)
        local reached = wait_and_settle(world, { 41, 42, 43 }, 1)
        expect.present(reached[41], "window 41 among the reached windows")
        expect.present(reached[42], "window 42 among the reached windows")
        expect.present(reached[43], "window 43 among the reached windows")
        expect.equal(world.application_window_reads, {
            ["com.apple.Safari"] = 4,
            ["com.microsoft.Word"] = 4,
        })
    end,

    a_window_without_an_application_is_described_as_a_window = function()
        local world = start_world()
        world.windows[41].is_unseen = false
        world.windows[42].is_unseen = false
        world.windows_without_application[41] = true
        local without_application = expect.present(_G.hs.window.get(41), "window 41")
        local of_word = expect.present(_G.hs.window.get(42), "window 42")
        expect.equal(track_windows.describe(without_application), 'a window "Window 1"')
        expect.equal(track_windows.describe(of_word), 'Microsoft Word window "Window 2"')
    end,
}
