local concealment_method = require("desktop_manager.core.concealment_method")
local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local profile_state = require("desktop_manager.core.profile_state")

return {
    a_window_that_no_profile_recorded_is_minimized_by_a_profile_with_a_layout = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["0"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local notes = world.create_window("com.microsoft.Word", "Notes.docx")
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[notes.id].is_minimized, true)
        expect.equal(controller_world.recorded_sight(controller, 1, notes.id), "out of sight")
        world.hotkeys["0"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local budget = world.create_window("com.microsoft.Word", "Budget.docx")
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["3"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[budget.id].is_minimized, false)
        expect.equal(world.windows[42].is_minimized, true)
    end,

    a_window_on_another_screen_moves_by_its_frame_and_its_id_without_a_desktop_switch = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.windows[41].space_id = 3
        world.windows[41].frame = { x = 0, y = 25, w = 600, h = 400 }
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[41].space_id, 8)
        controller_world.expect_frame_near(
            world.windows[41].frame,
            { x = 1440, y = 25, w = 1280, h = 1390 }
        )
        expect.equal(world.window_moves, { "41 to 8" })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.frames_set_out_of_view, {})
        expect.equal(world.notifications, {})
    end,

    a_window_that_stays_off_its_screen_is_not_moved_by_its_id = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.windows[41].space_id = 3
        world.windows[41].frame = { x = 0, y = 25, w = 600, h = 400 }
        world.frame_refusing_window_ids[41] = true
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[41].space_id, 3)
        expect.equal(world.window_moves, {})
        expect.equal(world.notifications, {
            'Safari window "Inbox" stayed off screen external 1'
                .. " (1 problems in the Hammerspoon console)",
        })
    end,

    an_unseen_window_in_place_is_not_moved_at_a_switch = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.window_moves, {})
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.windows[reading.id].is_unseen, true)
        expect.equal(world.menu_selections, {})
        expect.equal(world.notifications, {})
    end,

    a_switch_while_a_window_shows_in_full_screen_shows_a_desktop_first = function()
        local world = controller_world.start_world()
        world.displays[1].full_screen_space_ids = { 500 }
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].active_space_id = 500
        world.windows[42].frame = { x = 100, y = 100, w = 600, h = 500 }
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 3" })
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[42].space_id, 3)
        controller_world.expect_frame_near(
            world.windows[42].frame,
            { x = 720, y = 25, w = 720, h = 875 }
        )
        expect.equal(world.frames_set_out_of_view, {})
        expect.equal(world.notifications, {})
    end,

    a_step_that_raises_ends_the_switch_with_a_failure = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.swallows_timer_errors = true
        world.hotkeys["1"]()
        world.desktop_read_error = "macOS stopped answering"
        world.advance(60)
        expect.equal(controller.is_switch_or_restore_running, true)
        world.advance(40)
        expect.equal(controller.is_switch_or_restore_running, false)
        expect.equal(#world.timer_errors > 0, true)
        local message = "Desktop Manager stopped a switch that did not finish within 90 seconds"
            .. " (1 problems in the Hammerspoon console)"
        expect.equal(world.notifications, { message })
        local _, visible_count = controller_world.read_busy_messages(world)
        expect.equal(visible_count, 0)
    end,

    a_save_during_a_switch_records_nothing_until_its_end = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.url_handlers["desktop-manager"]("desktop-manager", { action = "save" })
        expect.equal(controller_world.recorded_sight(controller, 1, 41), "in sight")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, 41), "in sight")
        expect.equal(world.windows[41].is_minimized, false)
    end,

    a_window_reopened_on_a_desktop_not_visited_takes_over_its_records = function()
        local world, controller =
            controller_world.start_world({ match_windows_by = match_windows_by.ID })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["0"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 2, 42), "out of sight")
        world.close_window(42)
        local reopened = world.create_unseen_window("com.microsoft.Word", "Draft.docx", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(0.5)
        expect.equal(controller.is_switch_or_restore_running, true)
        expect.equal(controller_world.recorded_sight(controller, 2, reopened.id), "out of sight")
        expect.equal(controller_world.recorded_sight(controller, 2, 42), nil)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[reopened.id].space_id, 3)
        expect.equal(world.windows[reopened.id].is_minimized, false)
        expect.equal(world.menu_selections, {})
    end,

    the_hiding_setting_reaches_no_window_of_an_application_that_it_hides = function()
        local world = controller_world.start_world({
            concealment_method = concealment_method.HIDE_APPLICATIONS,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, true)
        expect.equal(world.window_moves, {})
        expect.equal(world.windows[reading.id].is_unseen, true)
    end,

    a_profile_records_a_window_that_hammerspoon_has_not_seen = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, reading.id), "in sight")
        local arrangement = profile_state.find_arrangement(
            controller.state,
            1,
            controller_world.MONITOR_CONFIGURATION_KEY
        )
        local record = arrangement.windows[#arrangement.windows]
        expect.equal(record.title, "Reading list")
        expect.equal(record.desktop_number, 3)
        expect.present(record.unit_frame, "the unit frame of the record")
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.window_moves, {})
    end,

    a_switch_brings_a_window_not_seen_into_view_and_minimizes_it = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(world.window_moves, { reading.id .. " to 3" })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.windows[reading.id].is_minimized, true)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(controller_world.read_busy_messages(world), {
            "Arranging Profile 1… please wait",
            "Arranging Profile 2… please wait",
            "Finding the windows on other desktops… please wait",
            "Arranging Profile 2… please wait",
        })
    end,

    the_first_profile_records_the_open_windows = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(controller_world.recorded_sight(controller, 1, 41), "in sight")
        expect.equal(controller_world.recorded_sight(controller, 1, 42), "in sight")
        expect.equal(world.window_operations, {})
        expect.equal(world.menubar_title, "◧ 1")
        expect.equal(world.notifications, {})
    end,

    a_new_profile_minimizes_the_windows_of_the_old_one = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(world.windows[41].is_minimized, true)
        expect.equal(world.windows[42].is_minimized, true)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        local arrangement = profile_state.find_arrangement(
            controller.state,
            1,
            controller_world.MONITOR_CONFIGURATION_KEY
        )
        expect.equal(arrangement.windows[1].desktop_number, 2)
        expect.equal(arrangement.windows[2].desktop_number, 1)
    end,

    the_old_profile_comes_back_on_its_desktops = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 2, news.id), "in sight")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.windows[news.id].is_minimized, true)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[42].is_minimized, false)
        expect.equal(world.windows[42].space_id, 3)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.notifications, {})
    end,

    a_switch_keeps_the_desktops_that_the_profile_recorded = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local arrangement = profile_state.find_arrangement(
            controller.state,
            1,
            controller_world.MONITOR_CONFIGURATION_KEY
        )
        expect.equal(arrangement.monitors[1].desktop_count, 4)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99 })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.notifications, {})
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[42].space_id, 3)
    end,

    the_hiding_setting_hides_an_application_of_the_old_profile = function()
        local world, controller = controller_world.start_world({
            concealment_method = concealment_method.HIDE_APPLICATIONS,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, true)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, true)
        expect.equal(world.windows[41].is_minimized, false)
    end,

    the_hiding_setting_minimizes_the_other_windows_of_a_shared_application = function()
        local world, controller = controller_world.start_world({
            concealment_method = concealment_method.HIDE_APPLICATIONS,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 2, news.id), "in sight")
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.windows[41].is_minimized, false)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.windows[news.id].is_minimized, true)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.notifications, {})
    end,

    a_window_that_two_profiles_record_at_the_same_place_is_left_alone = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.unminimize_window(41)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 2, 41), "in sight")
        expect.equal(controller_world.recorded_sight(controller, 2, 42), "out of sight")
        world.window_operations = {}
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.window_operations, { "unminimize 42", "minimize 42" })
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[41].space_id, 14)
    end,

    a_window_gets_the_frame_that_the_profile_entered_recorded = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.unminimize_window(41)
        world.advance(controller_world.SETTLE_SECONDS)
        local moved_frame = { x = 100, y = 100, w = 600, h = 500 }
        world.windows[41].frame = moved_frame
        world.window_operations = {}
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        controller_world.expect_frame_near(
            world.windows[41].frame,
            { x = 0, y = 25, w = 720, h = 875 }
        )
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        controller_world.expect_frame_near(world.windows[41].frame, moved_frame)
        expect.equal(
            world.window_operations,
            { "unminimize 42", "setFrame 41", "minimize 42", "setFrame 41" }
        )
        expect.equal(world.window_moves, { "41 to 3", "41 to 14", "41 to 3", "41 to 14" })
        expect.equal(world.frames_set_out_of_view, {})
    end,

    a_window_minimized_by_hand_stays_out_of_sight_in_that_profile = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.unminimize_window(41)
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.minimize_window(41)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, 41), "out of sight")
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[42].is_minimized, true)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, true)
        expect.equal(world.windows[42].is_minimized, false)
    end,

    a_reopened_window_keeps_its_place_in_every_profile = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        local reopened = world.create_window("com.microsoft.Word", "Draft.docx")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, reopened.id), "in sight")
        expect.equal(controller_world.recorded_sight(controller, 1, 42), nil)
        expect.equal(controller_world.recorded_sight(controller, 2, reopened.id), "in sight")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[reopened.id].is_minimized, false)
        expect.equal(world.windows[41].is_minimized, false)
    end,

    a_window_reopened_while_no_profile_is_active_is_renamed_at_the_next_switch = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["0"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        local reopened = world.create_window("com.microsoft.Word", "Draft.docx")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, reopened.id), nil)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, reopened.id), "in sight")
        expect.equal(world.windows[reopened.id].is_minimized, true)
    end,

    a_new_window_with_another_title_is_no_reopened_window = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        local other = world.create_window("com.microsoft.Word", "Budget.xlsx")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, other.id), nil)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[other.id].is_minimized, true)
    end,

    a_window_with_the_id_0_is_not_recorded = function()
        local world, controller = controller_world.start_world()
        world.windows[0] = nil
        local control_center = world.create_window("com.apple.Safari", "")
        world.windows[control_center.id] = nil
        control_center.id = 0
        world.windows[0] = control_center
        for index, window_id in ipairs(world.window_order) do
            if window_id ~= 41 and window_id ~= 42 then
                world.window_order[index] = 0
            end
        end
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, 0), nil)
        expect.equal(controller_world.recorded_sight(controller, 1, 41), "in sight")
    end,

    a_window_that_the_filter_drops_while_hidden_comes_back = function()
        local world = controller_world.start_world({
            concealment_method = concealment_method.HIDE_APPLICATIONS,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.applications["com.microsoft.Word"].is_dropped_by_filter_while_hidden = true
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, true)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.windows[42].is_minimized, false)
        expect.equal(world.windows[42].space_id, 3)
        expect.equal(world.notifications, {})
    end,

    an_unhide_by_the_user_leaves_the_windows_in_sight_for_the_next_capture = function()
        local world, controller = controller_world.start_world({
            concealment_method = concealment_method.HIDE_APPLICATIONS,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.unhide_application("com.apple.Safari")
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(controller_world.recorded_sight(controller, 2, 41), "in sight")
    end,

    an_application_that_stays_hidden_is_reported = function()
        local world = controller_world.start_world({
            concealment_method = concealment_method.HIDE_APPLICATIONS,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.applications["com.microsoft.Word"].ignores_unhide = true
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, true)
        expect.equal(world.notifications, {
            "Microsoft Word stayed hidden (1 problems in the Hammerspoon console)",
        })
    end,

    a_switch_to_a_recorded_profile_shows_a_message_until_it_ends = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        local _, visible_while_switching = controller_world.read_busy_messages(world)
        expect.equal(visible_while_switching, 1)
        world.advance(controller_world.SETTLE_SECONDS)
        local shown, visible_count = controller_world.read_busy_messages(world)
        expect.equal(shown, {
            "Arranging Profile 1… please wait",
            "Arranging Profile 2… please wait",
            "Arranging Profile 1… please wait",
        })
        expect.equal(visible_count, 0)
        expect.equal(world.alerts, { "Profile 1", "Profile 2" })
    end,

    a_window_on_another_desktop_of_its_screen_moves_back_by_its_id = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.windows[41].space_id = 64
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.window_moves, { "41 to 14" })
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.notifications, {})
    end,

    a_window_that_does_not_move_is_reported_at_each_switch = function()
        local world = controller_world.start_world()
        world.unmovable_window_ids[41] = true
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.windows[41].space_id = 64
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.window_moves, { "41 to 14" })
        expect.equal(world.windows[41].space_id, 64)
        world.hotkeys["1"]()
        world.windows[41].space_id = 14
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.window_moves, { "41 to 14", "41 to 64" })
        local function describe_failure(desktop_number)
            return string.format(
                'Safari window "Inbox" did not reach desktop %d of built-in: did not reach its'
                    .. " desktop within 1 seconds (1 problems in the Hammerspoon console)",
                desktop_number
            )
        end
        expect.equal(world.notifications, { describe_failure(2), describe_failure(3) })
    end,

    the_same_key_on_the_active_profile_deactivates_it = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["3"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["3"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, nil)
        expect.equal(world.menubar_title, "◧")
    end,

    a_window_that_accessibility_does_not_reach_in_view_goes_back_and_is_reported = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.unreachable_window_ids[reading.id] = true
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.window_moves, { reading.id .. " to 3", reading.id .. " to 64" })
        expect.equal(world.windows[reading.id].space_id, 64)
        expect.equal(world.notifications, {
            'Safari window "Reading list" stays on desktop 3,'
                .. " because accessibility did not reach it in view"
                .. " (2 problems in the Hammerspoon console)",
        })
    end,

    the_busy_message_shows_at_the_level_overlay = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local levels = {}
        for _, canvas in ipairs(world.canvases) do
            if #canvas.elements == 2 and canvas.elements[2].type == "text" then
                table.insert(levels, canvas.window_level)
            end
        end
        expect.equal(levels, { world.window_levels.overlay })
    end,

    the_console_gives_the_plan_and_the_duration_of_a_switch = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reading_list = world.add_window_of("com.apple.Safari", "Reading List", 3)
        world.advance(controller_world.SETTLE_SECONDS)
        local original_inspect = _G.hs.inspect
        _G.hs.inspect = expect.describe
        local is_switched, lines = pcall(controller_world.record_log_lines, world, function()
            world.hotkeys["1"]()
            world.advance(controller_world.SETTLE_SECONDS)
        end)
        _G.hs.inspect = original_inspect
        if not is_switched then
            error(lines, 0)
        end
        local placement_of_inbox = {
            window_id = 41,
            screen_uuid = "BUILTIN-UUID",
            slot_key = "built-in",
            desktop_number = 2,
            unit_frame = { x = 0.0, y = 0.0, w = 0.5, h = 1.0 },
        }
        local placement_of_draft = {
            window_id = 42,
            screen_uuid = "BUILTIN-UUID",
            slot_key = "built-in",
            desktop_number = 1,
            unit_frame = { x = 0.5, y = 0.0, w = 0.5, h = 1.0 },
        }
        local concealment =
            { bundle_ids_to_hide = {}, window_ids_to_minimize = { reading_list.id } }
        local plan = {
            bundle_ids_to_unhide = {},
            desktop_additions = {},
            unminimizations = { placement_of_inbox, placement_of_draft },
            placements = { placement_of_inbox, placement_of_draft },
            shown_desktops = {
                {
                    screen_uuid = "BUILTIN-UUID",
                    slot_key = "built-in",
                    desktop_number = 1,
                },
            },
        }
        expect.equal(lines, {
            "switching to profile 1: 2 of 2 saved windows open, concealing "
                .. expect.describe(concealment),
            "restoring profile 1: 2 of 2 saved windows open, plan " .. expect.describe(plan),
            "profile 1 is active after 1.1 seconds, with 0 problems",
        })
    end,

    the_console_names_a_reopened_window_with_its_new_id = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        local lines = controller_world.record_log_lines(world, function()
            world.create_window("com.microsoft.Word", "Draft.docx")
            world.advance(controller_world.SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            'Microsoft Word window "Draft.docx" was reopened as window 1001, which was 42',
        })
    end,

    the_console_counts_the_windows_that_a_switch_moves_into_view = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local lines = controller_world.record_log_lines(world, function()
            world.hotkeys["2"]()
            world.advance(controller_world.SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            "moving 1 windows into view to reach them",
            "switching to profile 2: 0 of 0 saved windows open, concealing <inspected>",
            "profile 2 is active after 0.1 seconds, with 0 problems",
        })
    end,
}
