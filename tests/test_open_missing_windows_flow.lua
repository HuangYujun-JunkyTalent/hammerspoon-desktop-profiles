local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local unmatched_window_action = require("desktop_manager.core.unmatched_window_action")

return {
    a_new_window_for_another_screen_goes_there_without_a_desktop_switch = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.applications["com.apple.Safari"].new_window_title = "Start Page"
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(41)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local opened = controller_world.find_window_titled(world, "Start Page")
        expect.equal(opened.space_id, 8)
        controller_world.expect_frame_near(opened.frame, { x = 1440, y = 25, w = 1280, h = 1390 })
        expect.equal(world.window_moves, { opened.id .. " to 8" })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.notifications, {})
    end,

    a_closed_window_gets_a_new_window_on_its_desktop = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(41)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local opened = controller_world.find_window_titled(world, "Start Page")
        expect.present(opened, "the window titled Start Page")
        expect.equal(opened.space_id, 14)
        expect.equal(opened.is_minimized, false)
        controller_world.expect_frame_near(opened.frame, { x = 0, y = 25, w = 720, h = 875 })
        expect.equal(world.menu_selections, { "com.apple.Safari New Window" })
        expect.equal(world.window_moves, { opened.id .. " to 14" })
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.mission_control_openings, 0)
        expect.equal(controller_world.recorded_sight(controller, 1, opened.id), "in sight")
        expect.equal(world.notifications, {})
    end,

    a_closed_window_is_forgotten_under_the_action_that_forgets = function()
        local world, controller = controller_world.start_world({
            unmatched_window_action = unmatched_window_action.FORGET,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(41)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.find_window_titled(world, "Start Page"), nil)
        expect.equal(world.menu_selections, {})
        expect.equal(controller_world.recorded_sight(controller, 1, 41), nil)
        expect.equal(controller_world.recorded_sight(controller, 1, 42), "in sight")
        expect.equal(world.notifications, {})
    end,

    a_window_with_the_recorded_title_is_taken_and_no_window_opens = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["0"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reopened = world.create_window("com.microsoft.Word", "Draft.docx")
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.menu_selections, {})
        expect.equal(world.windows[reopened.id].is_minimized, false)
        expect.equal(controller_world.recorded_sight(controller, 1, reopened.id), "in sight")
    end,

    the_policy_that_opens_new_windows_opens_one_despite_a_window_with_the_title = function()
        local world, controller = controller_world.start_world({
            match_windows_by = match_windows_by.ID,
            missing_window_policy = missing_window_policy.MATCH_ID_ALONE,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        local reopened = world.create_window("com.microsoft.Word", "Draft.docx")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, reopened.id), nil)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local opened = controller_world.find_window_titled(world, "Document1")
        expect.present(opened, "the window titled Document1")
        expect.equal(opened.is_minimized, false)
        expect.equal(world.windows[reopened.id].is_minimized, true)
        expect.equal(world.notifications, {})
    end,

    an_application_without_the_menu_item_gets_a_reopen = function()
        local world = controller_world.start_world()
        world.applications["com.microsoft.Word"].new_window_title = nil
        world.applications["com.microsoft.Word"].reopen_title = "Main Window"
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local opened = controller_world.find_window_titled(world, "Main Window")
        expect.present(opened, "the window titled Main Window")
        expect.equal(opened.space_id, 3)
        expect.equal(world.notifications, {})
    end,

    an_application_that_opens_no_window_is_reported = function()
        local world = controller_world.start_world()
        world.applications["com.microsoft.Word"].new_window_title = nil
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.notifications, {
            "Microsoft Word opened no new window after a reopen"
                .. " (1 problems in the Hammerspoon console)",
        })
    end,

    a_window_recorded_out_of_sight_and_closed_gets_no_new_window = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(41)
        world.hotkeys["3"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.menu_selections, {})
    end,

    an_application_that_is_not_running_is_launched = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local shopping = world.create_window("com.apple.Notes", "Shopping")
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.windows[shopping.id] = nil
        for index, window_id in ipairs(world.window_order) do
            if window_id == shopping.id then
                table.remove(world.window_order, index)
            end
        end
        world.applications["com.apple.Notes"].is_running = false
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local relaunched = nil
        for _, window in pairs(world.windows) do
            if window.title == "Shopping" then
                relaunched = window
            end
        end
        expect.present(relaunched, "the window titled Shopping")
        expect.equal(controller_world.recorded_sight(controller, 1, relaunched.id), "in sight")
        expect.equal(relaunched.is_minimized, false)
    end,

    the_console_names_the_window_that_the_profile_forgets = function()
        local world = controller_world.start_world({
            unmatched_window_action = unmatched_window_action.FORGET,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(41)
        local lines = controller_world.record_log_lines(world, function()
            world.hotkeys["1"]()
            world.advance(controller_world.SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            "switching to profile 1: 1 of 2 saved windows open, concealing <inspected>",
            'profile 1: Safari window "Inbox" is gone, and the profile forgets it',
            "restoring profile 1: 1 of 2 saved windows open, plan <inspected>",
            "profile 1 is active after 1.1 seconds, with 0 problems",
        })
    end,

    the_console_names_the_gone_and_unseen_records_in_their_order = function()
        local world = controller_world.start_world()
        world.add_window_of("com.apple.Safari", "Reading List", 3)
        local notes = world.add_window_of("com.microsoft.Word", "Notes.docx", 3)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.minimize_window(41)
        world.minimize_window(notes.id)
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(41)
        world.close_window(notes.id)
        world.windows[42].is_minimized = false
        world.windows[42].space_id = 64
        world.windows[42].is_unseen = true
        world.windows[42].is_ordered_out = true
        local lines = controller_world.record_log_lines(world, function()
            world.hotkeys["1"]()
            world.advance(controller_world.SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            "switching to profile 1: 1 of 4 saved windows open, concealing <inspected>",
            'Safari window "Inbox" is recorded out of sight and gone',
            'Microsoft Word window "Draft.docx" stays on desktop 64, where Hammerspoon has not'
                .. " seen it",
            'Microsoft Word window "Notes.docx" is recorded out of sight and gone',
            "restoring profile 1: 1 of 4 saved windows open, plan <inspected>",
            "profile 1 is active after 1.1 seconds, with 0 problems",
        })
    end,
}
