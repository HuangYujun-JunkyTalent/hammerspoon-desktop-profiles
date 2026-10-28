local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local profile_state = require("desktop_manager.core.profile_state")

local TWO_SCREEN_KEY = "built-in + 1 external"

---@param world table
---@param number integer
---@param configuration_key string
---@param is_managed boolean
local function tick_in_settings(world, number, configuration_key, is_managed)
    controller_world.find_menu_item(world, "Settings…").fn()
    world.post_to_webview("settings", {
        kind = "manage",
        number = number,
        configuration_key = configuration_key,
        is_managed = is_managed,
    })
end

---@param world table
---@param text string
---@return boolean whether an alert showed the text
local function has_alert(world, text)
    for _, alert in ipairs(world.alerts) do
        if alert == text then
            return true
        end
    end
    return false
end

return {
    a_profile_that_leaves_the_configuration_to_macos_becomes_active_and_moves_no_window = function()
        local world, controller = controller_world.start_world()
        tick_in_settings(world, 2, controller_world.MONITOR_CONFIGURATION_KEY, false)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(has_alert(world, "Profile 2 leaves built-in to macOS"), true)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[42].is_minimized, false)
        expect.equal(world.window_moves, {})
        expect.equal(world.mission_control_actions, {})
        expect.equal(profile_state.has_arrangements(controller.state, 2), false)
        expect.equal(world.saved_json.profiles["2"].unmanaged_configuration_keys, { "built-in" })
    end,

    a_switch_from_a_profile_that_leaves_the_configuration_to_macos_uses_the_record = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        tick_in_settings(world, 2, controller_world.MONITOR_CONFIGURATION_KEY, false)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.windows[41].space_id = 3
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller_world.find_record(controller, 1, 41).desktop_number, 2)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(profile_state.has_arrangements(controller.state, 2), false)
    end,

    a_switch_to_a_profile_without_a_record_of_the_configuration_records_it_as_new = function()
        local world, controller = controller_world.start_world()
        tick_in_settings(world, 1, controller_world.MONITOR_CONFIGURATION_KEY, false)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.present(
            profile_state.find_arrangement(
                controller.state,
                2,
                controller_world.MONITOR_CONFIGURATION_KEY
            ),
            "the record of profile 2"
        )
        expect.equal(profile_state.has_arrangements(controller.state, 1), false)
    end,

    a_change_into_a_configuration_left_to_macos_keeps_the_windows_and_the_desktops = function()
        local world, controller = controller_world.start_two_screen_world(
            { 3, 14, 64 },
            { 7, 8, 9, 10 }
        )
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        tick_in_settings(world, 1, controller_world.MONITOR_CONFIGURATION_KEY, false)
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 8, 9, 10 })
        expect.equal(world.mission_control_actions, {})
        expect.equal(has_alert(world, "Profile 1 leaves built-in to macOS"), true)
        expect.equal(
            profile_state.find_arrangement(
                controller.state,
                1,
                controller_world.MONITOR_CONFIGURATION_KEY
            ),
            nil
        )
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[41].space_id, 2000)
        expect.equal(world.windows[43].space_id, 2001)
        expect.present(
            profile_state.find_arrangement(controller.state, 1, TWO_SCREEN_KEY),
            "the record of the two screens"
        )
    end,

    the_settings_list_each_profile_with_the_configurations_it_recorded = function()
        local world, controller = controller_world.start_two_screen_world(
            { 3, 14, 64 },
            { 7, 8, 9, 10 }
        )
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        tick_in_settings(world, 3, "1 external", false)
        local choices =
            expect.present(controller.settings_window, "the window Settings").model.profile_choices
        expect.equal(choices.current_key, TWO_SCREEN_KEY)
        expect.equal(choices.configuration_keys, { "1 external", TWO_SCREEN_KEY })
        expect.equal(#choices.profiles, controller.settings.profile_count)
        expect.equal(choices.profiles[3].unmanaged_keys, { ["1 external"] = true })
        expect.equal(choices.profiles[1].unmanaged_keys, {})
        world.post_to_webview(
            "settings",
            { kind = "manage", number = 3.0, configuration_key = "1 external", is_managed = true }
        )
        expect.equal(profile_state.manages_configuration(controller.state, 3, "1 external"), true)
        world.post_to_webview(
            "settings",
            { kind = "manage", number = 3.5, configuration_key = "1 external", is_managed = false }
        )
        expect.equal(profile_state.manages_configuration(controller.state, 3, "1 external"), true)
    end,

    the_settings_mark_the_configuration_after_a_change_of_the_monitors = function()
        local world, controller = controller_world.start_two_screen_world(
            { 3, 14, 64 },
            { 7, 8, 9, 10 }
        )
        controller_world.find_menu_item(world, "Settings…").fn()
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        local choices =
            expect.present(controller.settings_window, "the window Settings").model.profile_choices
        expect.equal(choices.current_key, controller_world.MONITOR_CONFIGURATION_KEY)
    end,

    the_diagnostics_name_a_configuration_that_the_active_profile_leaves_to_macos = function()
        local world = controller_world.start_world()
        tick_in_settings(world, 1, controller_world.MONITOR_CONFIGURATION_KEY, false)
        world.hotkeys["1"]()
        local lines = controller_world.print_diagnostics(world)
        local is_named = false
        for _, line in ipairs(lines) do
            is_named = is_named or line == "profile 1 leaves built-in to macOS"
        end
        expect.equal(is_named, true)
    end,

    the_numbers_of_a_profile_that_leaves_the_configuration_to_macos_keep_their_defaults = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local defaults = profile_state.profile_or_default(controller.state, 1).app_numbers
        expect.equal(#defaults > 0, true)
        tick_in_settings(world, 1, controller_world.MONITOR_CONFIGURATION_KEY, false)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "3", app = "Microsoft Word" }
        )
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "release-app-number", number = "3" }
        )
        expect.equal(profile_state.profile_or_default(controller.state, 1).app_numbers, defaults)
        expect.equal(world.saved_json.profiles["1"].app_numbers, defaults)
        world.app_hotkeys["0"]()
        expect.equal(profile_state.profile_or_default(controller.state, 1).app_numbers, defaults)
        expect.equal(world.saved_json.profiles["1"].app_numbers, defaults)
    end,

    an_update_now_that_ends_a_pause_writes_it_in_a_configuration_left_to_macos = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        tick_in_settings(world, 1, controller_world.MONITOR_CONFIGURATION_KEY, false)
        controller.state = profile_state.with_active_profile_paused(controller.state)
        controller:write_state()
        expect.equal(world.saved_json.is_active_profile_paused, true)
        controller:save_arrangement_now()
        expect.equal(controller.state.is_active_profile_paused, false)
        expect.equal(world.saved_json.is_active_profile_paused, false)
        expect.equal(has_alert(world, "Profile 1 leaves built-in to macOS"), true)
    end,

    clearing_the_active_profile_in_a_configuration_left_to_macos_says_so = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        tick_in_settings(world, 1, controller_world.MONITOR_CONFIGURATION_KEY, false)
        world.alert_button = "Clear"
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "clear", profile = "1" }
        )
        expect.equal(
            world.alerts[#world.alerts],
            "Profile 1 is cleared and leaves built-in to macOS"
        )
    end,

    a_reset_without_a_record_of_a_configuration_left_to_macos_keeps_the_defaults = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local defaults = profile_state.profile_or_default(controller.state, 1).app_numbers
        expect.equal(#defaults > 0, true)
        tick_in_settings(world, 1, controller_world.MONITOR_CONFIGURATION_KEY, false)
        world.alert_button = "Clear"
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "clear", profile = "1" }
        )
        world.app_hotkeys["0"]()
        expect.equal(profile_state.profile_or_default(controller.state, 1).app_numbers, defaults)
        expect.equal(world.saved_json.profiles["1"].app_numbers, defaults)
    end,

    a_number_for_an_application_without_a_dock_icon_lets_hammerspoon_follow_it = function()
        local world = controller_world.start_world()
        local notes = world.applications["com.apple.Notes"]
        notes.is_running, notes.kind = true, 0
        local ignored = _G.hs.window.filter.ignoreAlways
        expect.equal(ignored["Notes"], true)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "4", app = "Notes" }
        )
        expect.equal(ignored["Notes"], false)
    end,
}
