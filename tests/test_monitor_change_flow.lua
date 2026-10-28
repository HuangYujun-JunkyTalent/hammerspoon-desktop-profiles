local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local fake_worlds = require("tests.fake_worlds")
local profile_state = require("desktop_manager.core.profile_state")

---A world in which profile 1 is active and has recorded the built-in display.
---@return table world
---@return ProfileController controller
local function start_world_with_a_record()
    local world, controller = controller_world.start_world()
    world.hotkeys["1"]()
    world.advance(controller_world.SETTLE_SECONDS)
    world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
    return world, controller
end

---@param world table
local function report_change_of_desktop(world)
    for _, callback in ipairs(world.space_watchers) do
        callback()
    end
end

---@param world table
---@return integer the calls of `allWindows` of every application so far
local function count_window_reads(world)
    local count = 0
    for _, reads in pairs(world.application_window_reads) do
        count = count + reads
    end
    return count
end

---@param controller ProfileController
---@return integer|nil the desktop that the record of profile 1 has the built-in display show
local function read_shown_desktop_number(controller)
    local arrangement = expect.present(
        profile_state.find_arrangement(
            controller.state,
            1,
            controller_world.MONITOR_CONFIGURATION_KEY
        ),
        "the record of profile 1"
    )
    return arrangement.monitors[1].shown_desktop_number
end

return {
    the_empty_desktops_that_macos_leaves_after_a_monitor_returns_are_removed = function()
        local world, controller = controller_world.start_two_screen_world(
            { 3, 14, 64 },
            { 7, 8, 9, 10 }
        )
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller.state.desktop_counts.kept, { ["built-in"] = 3, ["external 1"] = 4 })
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 8, 9 })
        expect.equal(world.mission_control_actions, { "remove 10" })
        expect.equal(world.is_mission_control_open, false)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller.state.desktop_counts.kept, { ["built-in"] = 3, ["external 1"] = 4 })
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.displays[2].space_ids, { 20, 2000, 2001, 2002 })
        expect.equal(world.windows[41].space_id, 2000)
        expect.equal(world.windows[43].space_id, 2001)
        expect.equal(world.windows[42].space_id, 3)
        expect.equal(world.mission_control_actions, {
            "remove 10",
            "add 2000",
            "add 2001",
            "add 2002",
            "remove 9",
            "remove 8",
        })
        expect.equal(world.mission_control_openings, 3)
        expect.equal(world.window_moves, { "41 to 3", "43 to 3", "41 to 2000", "43 to 2001" })
        expect.equal(world.frames_set_out_of_view, {})
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.notifications, {})
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller.state.desktop_counts.kept, { ["built-in"] = 3, ["external 1"] = 4 })
    end,

    a_window_that_hammerspoon_has_not_seen_returns_to_the_monitor = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.windows[43].is_unseen = true
        world.mission_control_actions = {}
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.window_moves, { "43 to 3", "41 to 3", "41 to 2000", "43 to 2001" })
        expect.equal(
            world.mission_control_actions,
            { "add 2000", "add 2001", "add 2002", "remove 9", "remove 8" }
        )
        expect.equal(world.frames_set_out_of_view, {})
        expect.equal(world.key_strokes, {})
        expect.equal(world.windows[43].space_id, 2001)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.notifications, {})
    end,

    a_restore_after_a_change_of_monitors_minimizes_no_window = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[news.id].is_minimized, false)
        expect.equal(world.windows[41].space_id, 2000)
        expect.equal(world.notifications, {})
    end,

    a_monitor_change_during_a_switch_is_restored_after_the_switch = function()
        local timing = fake_worlds.create_default_timing()
        timing.screen_settle_seconds = 0.5
        local world, controller = controller_world.start_world({ timing = timing })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(0.6)
        expect.equal(controller.is_switch_or_restore_running, true)
        world.advance(controller_world.SETTLE_SECONDS)
        local shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Arranging Profile 1 for built-in… please wait")
        expect.equal(controller.is_switch_or_restore_running, false)
        expect.equal(controller.are_saves_suspended, false)
        controller_world.expect_frame_near(
            world.windows[42].frame,
            { x = 756, y = 25, w = 756, h = 957 }
        )
    end,

    a_desktop_that_the_user_adds_stays_after_a_monitor_change = function()
        local world, controller = controller_world.start_two_screen_world(
            { 3, 14, 64 },
            { 7, 8, 9, 10 }
        )
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        table.insert(world.displays[1].space_ids, 99)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller.state.desktop_counts.kept, { ["built-in"] = 4, ["external 1"] = 4 })
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99, 8, 9 })
        expect.equal(world.mission_control_actions, { "remove 10" })
    end,

    a_monitor_change_without_an_active_profile_leaves_everything_to_macos = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 8, 9, 10 })
        expect.equal(world.alerts, {})
        expect.equal(world.notifications, {})
    end,

    a_profile_deactivated_while_the_monitors_settle_leaves_everything_to_macos = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.hotkeys["0"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 8, 9, 10 })
    end,

    a_screen_event_without_a_change_of_screens_restores_nothing = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.alerts, { "Profile 1" })
    end,

    a_screen_of_another_size_restores_the_arrangement = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        local _, visible_while_settling = controller_world.read_busy_messages(world)
        expect.equal(visible_while_settling, 1)
        world.advance(controller_world.SETTLE_SECONDS)
        local shown, visible_count = controller_world.read_busy_messages(world)
        expect.equal(shown, {
            "Arranging Profile 1… please wait",
            "Monitors changed, waiting for macOS… please wait",
            "Arranging Profile 1 for built-in… please wait",
        })
        expect.equal(visible_count, 0)
        expect.equal(world.alerts, { "Profile 1" })
    end,

    a_monitor_configuration_new_to_the_profile_is_left_to_macos = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.screens[1].name = "LG TV SSCR2"
        world.screens[1].frame = { x = 0, y = 25, w = 1872, h = 1053 }
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        local shown, visible_count = controller_world.read_busy_messages(world)
        expect.equal(shown, {
            "Arranging Profile 1… please wait",
            "Monitors changed, waiting for macOS… please wait",
        })
        expect.equal(visible_count, 0)
        expect.equal(world.alerts, {
            "Profile 1",
            "Profile 1 has no layout for 1 external yet, so the windows stay where macOS put them",
        })
    end,

    a_second_monitor_change_during_a_restore_keeps_the_layout = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local recorded_frame = controller_world.find_record(controller, 1, 42).unit_frame
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(3.1)
        expect.equal(controller.is_switch_or_restore_running, true)
        world.screens[1].frame = controller_world.BUILTIN_SCREEN.frame
        world.screen_watchers[1]()
        local is_message_shown_between = false
        for _ = 1, 100 do
            world.advance(0.05)
            if not controller.is_switch_or_restore_running and controller.screen_timer then
                expect.equal(controller.are_saves_suspended, true)
                is_message_shown_between = controller.busy_message_text
                    == "Monitors changed, waiting for macOS… please wait"
            end
        end
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(is_message_shown_between, true)
        expect.equal(controller_world.find_record(controller, 1, 42).unit_frame, recorded_frame)
        controller_world.expect_frame_near(
            world.windows[42].frame,
            { x = 720, y = 25, w = 720, h = 875 }
        )
        expect.equal(controller.are_saves_suspended, false)
    end,

    a_deactivation_during_a_restore_is_refused_with_an_alert = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(3.1)
        expect.equal(controller.is_switch_or_restore_running, true)
        world.hotkeys["0"]()
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
    end,

    a_save_while_the_monitors_settle_records_nothing = function()
        local world, controller = controller_world.start_two_screen_world(
            { 3, 14, 64 },
            { 7, 8, 9, 10 }
        )
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.url_handlers["desktop-manager"]("desktop-manager", { action = "save" })
        expect.equal(
            profile_state.find_arrangement(
                controller.state,
                1,
                controller_world.MONITOR_CONFIGURATION_KEY
            ),
            nil
        )
        world.advance(controller_world.SETTLE_SECONDS)
        expect.present(
            profile_state.find_arrangement(
                controller.state,
                1,
                controller_world.MONITOR_CONFIGURATION_KEY
            ),
            "the arrangement of profile 1"
        )
    end,

    a_restore_after_a_change_of_monitors_leaves_a_window_in_full_screen_first = function()
        local world = controller_world.start_world()
        world.displays[1].full_screen_space_ids = { 500 }
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.displays[1].active_space_id = 500
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 3" })
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.frames_set_out_of_view, {})
        controller_world.expect_frame_near(
            world.windows[42].frame,
            { x = 756, y = 25, w = 756, h = 957 }
        )
        expect.equal(world.notifications, {})
    end,

    the_first_record_of_a_configuration_holds_the_desktops_that_macos_moved_there = function()
        local world, controller = controller_world.start_two_screen_world(
            { 3, 14, 64 },
            { 7, 8, 9, 10 }
        )
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local arrangement = expect.present(
            profile_state.find_arrangement(
                controller.state,
                1,
                controller_world.MONITOR_CONFIGURATION_KEY
            ),
            "the arrangement of profile 1"
        )
        expect.equal(arrangement.monitors[1].desktop_count, 5)
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        local space_ids = world.displays[1].space_ids
        expect.equal(#space_ids, 5)
        expect.equal(world.windows[41].space_id, space_ids[4])
        expect.equal(world.windows[43].space_id, space_ids[5])
    end,

    a_change_of_desktop_records_the_shown_desktop_and_reads_no_window = function()
        local world, controller = start_world_with_a_record()
        local runs_before, filter_reads_before = world.server_list_run_count, world.filter_reads
        local window_reads_before = count_window_reads(world)
        world.displays[1].active_space_id = 14
        report_change_of_desktop(world)
        world.advance(1)
        expect.equal(read_shown_desktop_number(controller), 1)
        world.advance(2)
        expect.equal(read_shown_desktop_number(controller), 2)
        local saved_arrangements = world.saved_json.profiles["1"].arrangements
        local saved = saved_arrangements[controller_world.MONITOR_CONFIGURATION_KEY]
        expect.equal(saved.monitors[1].shown_desktop_number, 2)
        world.advance(5)
        expect.equal(world.server_list_run_count, runs_before)
        expect.equal(world.filter_reads, filter_reads_before)
        expect.equal(count_window_reads(world), window_reads_before)
    end,

    a_change_of_the_monitors_right_after_a_change_of_desktop_stops_its_record = function()
        local world, controller = controller_world.start_two_screen_world(
            { 3, 14, 64 },
            { 7, 8, 9, 10 }
        )
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.displays[2].active_space_id = 9
        report_change_of_desktop(world)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        expect.equal(controller.desktops_timer, nil)
    end,

    a_change_of_desktop_that_removes_a_desktop_updates_the_whole_record = function()
        local world, controller = start_world_with_a_record()
        local filter_reads_before = world.filter_reads
        world.displays[1].space_ids = { 3, 14 }
        report_change_of_desktop(world)
        world.advance(3)
        expect.equal(controller.state.desktop_counts.last_reading.counts["built-in"], 2)
        expect.equal(controller.state.desktop_counts.kept["built-in"], 2)
        expect.equal(world.filter_reads > filter_reads_before, true)
    end,

    a_change_of_desktop_without_an_active_profile_counts_a_new_desktop = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 65 }
        report_change_of_desktop(world)
        world.advance(3)
        expect.equal(world.saved_json.desktop_counts.kept["built-in"], 4)
    end,

    a_change_of_desktop_while_a_save_waits_leaves_the_record_to_the_save = function()
        local world, controller = start_world_with_a_record()
        controller:schedule_save()
        world.displays[1].active_space_id = 14
        report_change_of_desktop(world)
        expect.equal(controller.desktops_timer, nil)
        world.advance(3)
        expect.equal(read_shown_desktop_number(controller), 2)
    end,
}
