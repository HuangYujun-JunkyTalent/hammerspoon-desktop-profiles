local concealment_method = require("desktop_manager.core.concealment_method")
local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local fake_worlds = require("tests.fake_worlds")
local mission_control_desktops = require("desktop_manager.macos.mission_control_desktops")
local profile_state = require("desktop_manager.core.profile_state")

---@param world table
local function leave_notes_to_macos(world)
    controller_world.open_app_pool_window(world)
    world.post_to_webview("appPool", {
        kind = "tick",
        bundle_id = "com.apple.Notes",
        app_name = "Notes",
        is_listed = true,
    })
end

---Puts a window of Notes, which the desktop manager leaves to macOS, on a desktop beyond the 3
---desktops of profile 1 while profile 2 is active, changes the window as `change_window` does, and
---switches to profile 1.
---@param change_window fun(world: table, window: table)
---@return table world
---@return table window the window of Notes
local function switch_with_a_window_left_to_macos(change_window)
    local world = controller_world.start_world()
    world.hotkeys["1"]()
    world.advance(controller_world.SETTLE_SECONDS)
    world.hotkeys["2"]()
    world.advance(controller_world.SETTLE_SECONDS)
    leave_notes_to_macos(world)
    world.displays[1].space_ids = { 3, 14, 64, 99 }
    local shopping = world.add_window_of("com.apple.Notes", "Shopping", 99)
    change_window(world, shopping)
    world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
    world.hotkeys["1"]()
    world.advance(controller_world.SETTLE_SECONDS)
    return world, shopping
end

return {
    a_switch_shows_the_desktop_that_each_screen_showed = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.displays[1].active_space_id = 14
        world.displays[2].active_space_id = 9
        world.focused_display_uuid = controller_world.BUILTIN_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.displays[2].active_space_id = 7
        world.focused_display_uuid = controller_world.DELL_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 9", "show 14" })
        expect.equal(world.mission_control_openings, 2)
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.displays[2].active_space_id, 9)
        expect.equal(world.focused_display_uuid, controller_world.BUILTIN_SCREEN.uuid)
        local shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown - 2], "Showing desktop 3 of external 1… please wait")
        expect.equal(shown[#shown], "Showing desktop 2 of built-in… please wait")
        expect.equal(world.notifications, {})
    end,

    a_switch_ends_with_the_focus_on_the_screen_that_had_it = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.displays[1].active_space_id = 14
        world.displays[2].active_space_id = 8
        world.focused_display_uuid = controller_world.DELL_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.focused_display_uuid = controller_world.BUILTIN_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 14" })
        expect.equal(world.focused_display_uuid, controller_world.DELL_SCREEN.uuid)
        expect.equal(world.focused_window_id, 41)
    end,

    a_saved_state_of_the_first_version_shows_its_desktop_without_the_moved_desktops = function()
        local saved_state = {
            format_version = 1,
            monitor_matching = "by_count",
            desktop_counts = { kept = { ["built-in"] = 3 } },
            profiles = {
                ["1"] = {
                    number = 1,
                    arrangements = {
                        ["built-in"] = {
                            monitor_configuration_key = "built-in",
                            monitors = { { slot_key = "built-in", desktop_count = 5 } },
                            focus = { slot_key = "built-in", desktop_number = 3 },
                            windows = {
                                {
                                    window_id = 41,
                                    bundle_id = "com.apple.Safari",
                                    app_name = "Safari",
                                    title = "Inbox",
                                    slot_key = "built-in",
                                    desktop_number = 2,
                                    unit_frame = { x = 0, y = 0, w = 0.5, h = 1 },
                                    is_out_of_sight = false,
                                },
                            },
                        },
                    },
                },
            },
        }
        local world, controller = controller_world.start_world(nil, saved_state)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 64" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.displays[1].active_space_id, 64)
        local arrangement = expect.present(
            profile_state.find_arrangement(
                controller.state,
                1,
                controller_world.MONITOR_CONFIGURATION_KEY
            ),
            "the arrangement of profile 1"
        )
        expect.equal(arrangement.monitors, {
            { slot_key = "built-in", desktop_count = 3, shown_desktop_number = 3 },
        })
        expect.equal(world.saved_json.format_version, 2)
        expect.equal(world.notifications, {})
    end,

    a_switch_removes_the_empty_desktops_beyond_the_profile_and_adds_them_back = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 98, 99 }
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.mission_control_actions, { "remove 99", "remove 98" })
        expect.equal(world.mission_control_openings, 1)
        local shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Removing 2 empty desktops from built-in… please wait")
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 2000, 2001 })
        shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown - 1], "Adding 2 desktops to built-in… please wait")
        expect.equal(shown[#shown], "Arranging Profile 2… please wait")
        expect.equal(world.windows_moved_by_removal, {})
        expect.equal(world.notifications, {})
    end,

    a_window_left_to_macos_keeps_its_desktop_beyond_the_profile_in_sight = function()
        local world, shopping = switch_with_a_window_left_to_macos(function() end)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99 })
        expect.equal(world.windows[shopping.id].space_id, 99)
        expect.equal(world.mission_control_actions, {})
    end,

    a_minimized_window_left_to_macos_keeps_its_desktop_beyond_the_profile = function()
        local world, shopping = switch_with_a_window_left_to_macos(function(world, window)
            world.minimize_window(window.id)
        end)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99 })
        expect.equal(world.windows[shopping.id].space_id, 99)
        expect.equal(world.mission_control_actions, {})
    end,

    a_window_of_a_hidden_application_left_to_macos_keeps_its_desktop_beyond_the_profile = function()
        local world, shopping = switch_with_a_window_left_to_macos(function(world)
            world.applications["com.apple.Notes"].is_hidden = true
        end)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99 })
        expect.equal(world.windows[shopping.id].space_id, 99)
        expect.equal(world.mission_control_actions, {})
    end,

    a_window_that_a_hidden_application_keeps_ordered_out_keeps_no_desktop = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        leave_notes_to_macos(world)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        local closed = world.create_unseen_window("com.apple.Notes", "New Note", 99)
        world.windows[closed.id].is_ordered_out = true
        world.applications["com.apple.Notes"].is_hidden = true
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    a_window_that_its_application_keeps_ordered_out_keeps_no_desktop_beyond_the_profile = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        leave_notes_to_macos(world)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        local closed = world.create_unseen_window("com.apple.Notes", "New Note", 99)
        world.windows[closed.id].is_ordered_out = true
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    a_window_of_a_managed_application_that_the_switch_hides_keeps_no_desktop = function()
        local world = controller_world.start_world({
            concealment_method = concealment_method.HIDE_APPLICATIONS,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.add_window_of("com.apple.Notes", "Shopping", 99)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.apple.Notes"].is_hidden, true)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.windows_moved_by_removal, {})
    end,

    a_window_of_an_application_without_a_dock_icon_keeps_its_desktop = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.applications["com.apple.Notes"].kind = 0
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        local settings = world.add_window_of("com.apple.Notes", "Display settings", 99)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller:does_window_keep_desktop(settings.id), true)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99 })
    end,

    a_window_on_every_desktop_keeps_none_of_them = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        leave_notes_to_macos(world)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        local sticky = world.add_window_of("com.apple.Notes", "Sticky", 99)
        world.windows[sticky.id].is_on_every_desktop = true
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    a_minimized_window_keeps_no_desktop_beyond_the_profile = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.displays[1].active_space_id = 99
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[news.id].is_minimized, true)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.windows[news.id].space_id, 3)
        expect.equal(world.windows_moved_by_removal, {})
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 2000 })
        expect.equal(world.windows[news.id].space_id, 2000)
        expect.equal(world.windows[news.id].is_minimized, false)
        expect.equal(world.window_moves, { news.id .. " to 2000" })
        expect.equal(world.mission_control_actions, { "remove 99", "add 2000" })
        expect.equal(world.notifications, {})
    end,

    the_desktop_in_view_beyond_the_profile_goes_after_the_recorded_desktop_shows = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.displays[1].active_space_id = 99
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 3", "remove 99" })
        expect.equal(world.mission_control_openings, 2)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    a_desktop_in_view_beyond_the_profile_goes_when_the_profile_records_no_shown_desktop = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local arrangement =
            controller.state.profiles["1"].arrangements[controller_world.MONITOR_CONFIGURATION_KEY]
        arrangement.monitors[1].shown_desktop_number = nil
        arrangement.focused_slot_key = nil
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.displays[1].active_space_id = 99
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 64", "remove 99" })
        expect.equal(world.displays[1].active_space_id, 64)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    mission_control_opens_once_for_the_additions_of_two_screens = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14 }
        world.displays[2].space_ids = { 7, 8, 9 }
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "add 2000", "add 2001" })
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.displays[1].space_ids, { 3, 14, 2000 })
        expect.equal(world.displays[2].space_ids, { 7, 8, 9, 2001 })
        local shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown - 2], "Adding 2 desktops… please wait")
    end,

    mission_control_opens_once_for_the_removals_and_the_last_press = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].active_space_id = 14
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.displays[1].active_space_id = 3
        world.mission_control_actions = {}
        world.mission_control_openings = 0
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {
            "add 2000",
            "add 2001",
            "add 2002",
            "remove 9",
            "remove 8",
            "show 14",
        })
        expect.equal(world.mission_control_openings, 2)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.notifications, {})
        local shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Removing 2 empty desktops from built-in… please wait")
    end,

    an_extra_desktop_in_view_on_the_screen_of_the_focus_goes_after_its_own_opening = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].active_space_id = 9
        world.mission_control_actions = {}
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {
            "add 2000",
            "add 2001",
            "add 2002",
            "show 3",
            "remove 9",
            "remove 8",
        })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.windows[43].space_id, 2001)
        expect.equal(world.notifications, {})
    end,

    a_window_keeps_its_desktop_from_a_removal_while_in_sight_or_left_to_macos = function()
        local world, controller = controller_world.start_world()
        expect.equal(controller:does_window_keep_desktop(41), true)
        world.minimize_window(41)
        expect.equal(controller:does_window_keep_desktop(41), false)
        world.minimize_window(42)
        controller_world.open_app_pool_window(world)
        world.post_to_webview("appPool", {
            kind = "tick",
            bundle_id = "com.microsoft.Word",
            app_name = "Microsoft Word",
            is_listed = true,
        })
        expect.equal(controller:does_window_keep_desktop(42), true)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        expect.equal(controller:does_window_keep_desktop(reading.id), false)
        expect.equal(controller:does_window_keep_desktop(999), false)
    end,

    a_desktop_after_the_tenth_shows_through_mission_control = function()
        local world = controller_world.start_two_screen_world(
            { 3, 14, 64, 65, 66 },
            { 7, 8, 9, 10, 11, 12 }
        )
        local result = "pending"
        mission_control_desktops.show_space(
            12,
            fake_worlds.create_default_timing(),
            function(error_message)
                result = error_message or "shown"
            end
        )
        world.advance(5)
        expect.equal(result, "shown")
        expect.equal(world.displays[2].active_space_id, 12)
        expect.equal(world.focused_display_uuid, controller_world.DELL_SCREEN.uuid)
        expect.equal(world.mission_control_actions, { "show 12" })
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.key_strokes, {})
        expect.equal(world.tasks, {})
    end,

    a_switch_gives_the_focus_to_a_window_when_the_press_leaves_the_focus = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.press_moves_focus = false
        local notes = world.add_window_of("com.microsoft.Word", "Notes.docx", 14)
        world.displays[1].active_space_id = 14
        world.displays[2].active_space_id = 9
        world.focused_display_uuid = controller_world.BUILTIN_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.displays[2].active_space_id = 7
        world.focused_display_uuid = controller_world.DELL_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 9", "show 14" })
        expect.equal(world.focused_display_uuid, controller_world.BUILTIN_SCREEN.uuid)
        expect.equal(world.focused_window_id, notes.id)
    end,

    a_switch_waits_for_the_release_of_the_modifiers_before_mission_control_opens = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14 }
        world.held_modifiers = { cmd = true, alt = true, shift = true }
        world.hotkeys["1"]()
        world.advance(1)
        expect.equal(world.mission_control_openings, 0)
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "add 2000" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 2000 })
        expect.equal(world.notifications, {})
    end,

    a_modifier_held_through_a_switch_keeps_mission_control_closed_and_is_reported = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14 }
        world.held_modifiers = { cmd = true, alt = true, shift = true }
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_openings, 0)
        expect.equal(world.displays[1].space_ids, { 3, 14 })
        expect.equal(#world.notifications, 1)
        expect.present(
            world.notifications[1]:match("^Release the modifier keys"),
            "the notification to release the modifier keys"
        )
    end,

    the_check_before_a_removal_walks_every_window_once = function()
        local world, controller = controller_world.start_world()
        controller_world.open_app_pool_window(world)
        world.post_to_webview("appPool", {
            kind = "tick",
            bundle_id = "com.microsoft.Word",
            app_name = "Microsoft Word",
            is_listed = true,
        })
        local first = world.add_window_of("com.microsoft.Word", "First.docx", 64)
        local second = world.add_window_of("com.microsoft.Word", "Second.docx", 64)
        world.applications["com.microsoft.Word"].is_dropped_by_filter_while_hidden = true
        world.applications["com.microsoft.Word"].is_hidden = true
        local reads_before, running_count = {}, 0
        for bundle_id, application in pairs(world.applications) do
            reads_before[bundle_id] = world.application_window_reads[bundle_id] or 0
            running_count = running_count + (application.is_running and 1 or 0)
        end
        expect.equal(controller:find_window_that_keeps_desktop({ 42, first.id, second.id }), 42)
        local read_count = 0
        for bundle_id, count in pairs(reads_before) do
            local reads = (world.application_window_reads[bundle_id] or 0) - count
            expect.equal(reads <= 1, true)
            read_count = read_count + reads
        end
        expect.equal(read_count, running_count)
    end,

    the_console_names_the_empty_desktops_that_stay_and_the_desktops_removed = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        leave_notes_to_macos(world)
        world.displays[1].space_ids = { 3, 14, 64, 97, 98, 99 }
        world.add_window_of("com.apple.Notes", "Shopping", 98)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local lines = controller_world.record_log_lines(world, function()
            world.hotkeys["1"]()
            world.advance(controller_world.SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            "switching to profile 1: 2 of 2 saved windows open, concealing <inspected>",
            "restoring profile 1: 2 of 2 saved windows open, plan <inspected>",
            "built-in keeps 2 desktops beyond its 3, because they show or hold a window, or lie"
                .. " below one that does, as the empty desktops 97",
            "removing the empty desktops 99 beyond desktop 3 of built-in",
            "0.00 seconds for the release of the modifiers, 0.00 seconds until Mission Control"
                .. " showed",
            "profile 1 is active after 2.3 seconds, with 0 problems",
        })
    end,
}
