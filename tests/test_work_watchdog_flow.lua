local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local fake_worlds = require("tests.fake_worlds")

---Makes the desktops unreadable once Mission Control opens, so that the step that runs then raises
---and leaves Mission Control open.
---@param world table
local function make_desktops_unreadable_once_mission_control_opens(world)
    world.on_mission_control_open = function()
        world.desktop_read_error = "macOS stopped answering"
    end
end

local WATCHDOG_MESSAGE = "Desktop Manager stopped a switch that did not finish within 90 seconds"
    .. " (1 problems in the Hammerspoon console)"

return {
    a_switch_that_the_watchdog_stopped_removes_no_desktop = function()
        local timing = fake_worlds.create_default_timing()
        timing.busy_watchdog_seconds = 0.5
        local world, controller = controller_world.start_world({ timing = timing })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 98, 99 }
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.mission_control_actions = {}
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.notifications, {
            "Desktop Manager stopped a switch that did not finish within 0.5 seconds"
                .. " (1 problems in the Hammerspoon console)",
        })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 98, 99 })
        expect.equal(world.is_mission_control_open, false)
        expect.equal(controller.is_switch_or_restore_running, false)
    end,

    the_watchdog_closes_mission_control_after_a_step_that_raised_while_it_showed = function()
        local world, controller = controller_world.start_world()
        world.displays[1].active_space_id = 14
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.swallows_timer_errors = true
        make_desktops_unreadable_once_mission_control_opens(world)
        world.hotkeys["1"]()
        world.advance(5)
        expect.equal(world.is_mission_control_open, true)
        expect.equal(#world.timer_errors > 0, true)
        world.desktop_read_error = nil
        world.advance(90)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(controller.is_switch_or_restore_running, false)
        expect.equal(world.notifications, { WATCHDOG_MESSAGE })
    end,

    the_watchdog_resumes_the_saves_after_a_restore_that_raised = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.swallows_timer_errors = true
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(3.1)
        expect.equal(controller.is_switch_or_restore_running, true)
        world.desktop_read_error = "macOS stopped answering"
        world.advance(91)
        world.desktop_read_error = nil
        expect.equal(#world.timer_errors > 0, true)
        expect.equal(controller.is_switch_or_restore_running, false)
        expect.equal(controller.are_saves_suspended, false)
        expect.equal(world.notifications, { WATCHDOG_MESSAGE })
        world.windows[42].frame = { x = 100, y = 125, w = 600, h = 500 }
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local unit_frame = controller_world.find_record(controller, 1, 42).unit_frame
        expect.equal(math.abs(unit_frame.x - 100 / 1512) < 0.001, true)
    end,

    the_watchdog_ends_a_press_that_never_called_back = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.swallows_timer_errors = true
        make_desktops_unreadable_once_mission_control_opens(world)
        world.app_hotkeys["2"]()
        world.advance(5)
        expect.equal(controller.is_press_running, true)
        world.desktop_read_error = nil
        world.advance(90)
        expect.equal(controller.is_press_running, false)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.notifications, { WATCHDOG_MESSAGE })
        local _, visible_count = controller_world.read_busy_messages(world)
        expect.equal(visible_count, 0)
    end,
}
