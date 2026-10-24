local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local profile_state = require("desktop_manager.core.profile_state")

---A start of the desktop manager one minute after the start of macOS, as at a login.
local SECONDS_AFTER_LOGIN = 60

---The start of macOS after a restart, a day after the start under which the worlds run by default.
local MACOS_START_TIME_AFTER_RESTART = 1729586400

---@return table the state file of a world in which profile 1 is active and recorded both windows
local function record_profile_1()
    local world = controller_world.start_world()
    world.hotkeys["1"]()
    world.advance(controller_world.SETTLE_SECONDS)
    world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
    return world.saved_json
end

---@param setting_changes table|nil
---@return table world
---@return ProfileController controller
---@return table saved the state file that the start found
local function start_after_login(setting_changes)
    local saved = record_profile_1()
    local world, controller = controller_world.start_world(setting_changes, saved, {
        seconds_since_macos_start = SECONDS_AFTER_LOGIN,
        macos_start_time = MACOS_START_TIME_AFTER_RESTART,
    })
    return world, controller, saved
end

---@param world table
---@return boolean whether a line of the console names a pause
local function has_pause_line(world)
    for _, line in ipairs(world.log_lines) do
        if line:find("paused", 1, true) then
            return true
        end
    end
    return false
end

---@param controller ProfileController
---@param saved table
local function expect_profile_1_as_saved(controller, saved)
    expect.equal(controller.state.profiles["1"], saved.profiles["1"])
end

return {
    a_start_soon_after_macos_pauses_the_active_profile_and_says_so = function()
        local world, controller = start_after_login()
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(controller.state.is_active_profile_paused, true)
        expect.equal(world.saved_json.is_active_profile_paused, true)
        expect.equal(
            world.log_lines[1],
            "profile 1 is paused, because Hammerspoon started 60 seconds after macOS, less than"
                .. " pause_after_macos_start_seconds of 300, and activating profile 1 restores"
                .. " its layout"
        )
    end,

    a_start_at_the_setting_or_with_the_setting_0_pauses_nothing = function()
        local saved = record_profile_1()
        local _, at_setting = controller_world.start_world(
            nil,
            saved,
            { seconds_since_macos_start = 300, macos_start_time = MACOS_START_TIME_AFTER_RESTART }
        )
        expect.equal(at_setting.state.is_active_profile_paused, false)
        local _, turned_off = controller_world.start_world(
            { pause_after_macos_start_seconds = 0 },
            saved,
            {
                seconds_since_macos_start = SECONDS_AFTER_LOGIN,
                macos_start_time = MACOS_START_TIME_AFTER_RESTART,
            }
        )
        expect.equal(turned_off.state.is_active_profile_paused, false)
    end,

    a_reload_during_the_pause_keeps_it_also_after_the_setting = function()
        local first_world = start_after_login()
        local world, controller = controller_world.start_world(
            { pause_after_macos_start_seconds = 0 },
            first_world.saved_json,
            { macos_start_time = MACOS_START_TIME_AFTER_RESTART }
        )
        expect.equal(controller.state.is_active_profile_paused, true)
        expect.equal(
            world.log_lines[1],
            "profile 1 stays paused, as the state file says, and activating profile 1 restores"
                .. " its layout"
        )
    end,

    a_second_start_within_the_setting_after_the_end_of_the_pause_pauses_nothing = function()
        local routes = {
            function(world)
                world.hotkeys["1"]()
            end,
            function(world)
                world.hotkeys["2"]()
            end,
            function(world)
                world.hotkeys["0"]()
                world.advance(controller_world.SETTLE_SECONDS)
                world.hotkeys["1"]()
            end,
        }
        for _, route in ipairs(routes) do
            local first_world = start_after_login()
            route(first_world)
            first_world.advance(controller_world.SETTLE_SECONDS)
            local world, controller = controller_world.start_world(nil, first_world.saved_json, {
                seconds_since_macos_start = 200,
                macos_start_time = MACOS_START_TIME_AFTER_RESTART,
            })
            expect.present(controller.state.active_profile_number, "an active profile")
            expect.equal(controller.state.is_active_profile_paused, false)
            expect.equal(has_pause_line(world), false)
        end
    end,

    a_start_after_a_new_start_of_macos_pauses_again = function()
        local first_world = start_after_login()
        first_world.hotkeys["2"]()
        first_world.advance(controller_world.SETTLE_SECONDS)
        local _, controller = controller_world.start_world(nil, first_world.saved_json, {
            seconds_since_macos_start = SECONDS_AFTER_LOGIN,
            macos_start_time = MACOS_START_TIME_AFTER_RESTART + 3600,
        })
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(controller.state.is_active_profile_paused, true)
    end,

    a_start_that_cannot_read_the_start_of_macos_keeps_the_one_of_the_state = function()
        local first_world = start_after_login()
        first_world.hotkeys["1"]()
        first_world.advance(controller_world.SETTLE_SECONDS)
        local unread_world = controller_world.start_world(
            nil,
            first_world.saved_json,
            { seconds_since_macos_start = 120, macos_start_time = false }
        )
        unread_world.hotkeys["1"]()
        unread_world.advance(controller_world.SETTLE_SECONDS)
        local _, controller = controller_world.start_world(
            nil,
            unread_world.saved_json,
            { seconds_since_macos_start = 200, macos_start_time = MACOS_START_TIME_AFTER_RESTART }
        )
        expect.equal(controller.state.is_active_profile_paused, false)
    end,

    the_updates_change_no_record_and_no_number_of_the_paused_profile = function()
        local world, controller, saved = start_after_login()
        world.minimize_window(42)
        world.create_window("com.apple.Notes", "Shopping")
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect_profile_1_as_saved(controller, saved)
    end,

    a_press_of_the_list_during_the_pause_records_no_shown_desktop = function()
        local world, controller, saved = start_after_login()
        local entries = profile_state.profile_or_default(controller.state, 1).app_numbers
        expect.equal(entries[2].bundle_id, "com.apple.Safari")
        world.app_hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.displays[1].active_space_id, 14)
        expect_profile_1_as_saved(controller, saved)
    end,

    a_change_of_the_monitors_during_the_pause_restores_nothing = function()
        local world, controller, saved = start_after_login()
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.windows[42].frame = { x = 0, y = 25, w = 400, h = 400 }
        world.disconnect_screen(controller_world.DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[42].frame, { x = 0, y = 25, w = 400, h = 400 })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.alerts, {})
        expect.equal(controller_world.read_busy_messages(world), {})
        expect_profile_1_as_saved(controller, saved)
    end,

    a_change_of_the_monitors_during_a_press_in_the_pause_shows_no_message_after_it = function()
        local world = start_after_login()
        world.app_hotkeys["2"]()
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        local shown, visible_count = controller_world.read_busy_messages(world)
        expect.equal(shown, { "Showing desktop 2 of built-in… please wait" })
        expect.equal(visible_count, 0)
    end,

    another_profile_during_the_pause_switches_without_the_update_and_ends_the_pause = function()
        local world, controller, saved = start_after_login()
        world.minimize_window(42)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(controller.state.is_active_profile_paused, false)
        expect_profile_1_as_saved(controller, saved)
    end,

    the_deactivation_during_the_pause_updates_nothing_and_ends_the_pause = function()
        local world, controller, saved = start_after_login()
        world.minimize_window(42)
        world.hotkeys["0"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, nil)
        expect.equal(controller.state.is_active_profile_paused, false)
        expect_profile_1_as_saved(controller, saved)
    end,

    each_route_of_the_paused_profile_restores_its_layout_and_ends_the_pause = function()
        local routes = {
            function(world)
                world.hotkeys["1"]()
            end,
            function(world)
                world.url_handlers["desktop-manager"](
                    "desktop-manager",
                    { action = "activate", profile = "1" }
                )
            end,
            function(world)
                world.url_handlers["desktop-manager"](
                    "desktop-manager",
                    { action = "toggle", profile = "1" }
                )
            end,
            function(world)
                controller_world.find_menu_item(world, "1  Profile 1").fn()
            end,
        }
        for _, route in ipairs(routes) do
            local world, controller = start_after_login()
            world.minimize_window(42)
            local news = world.add_window_of("com.apple.Safari", "News", 3)
            route(world)
            world.advance(controller_world.SETTLE_SECONDS)
            expect.equal(controller.state.active_profile_number, 1)
            expect.equal(controller.state.is_active_profile_paused, false)
            expect.equal(world.windows[42].is_minimized, false)
            expect.equal(world.windows[news.id].is_minimized, true)
            world.minimize_window(42)
            world.advance(controller_world.SETTLE_SECONDS)
            expect.equal(controller_world.recorded_sight(controller, 1, 42), "out of sight")
        end
    end,

    the_url_that_deactivates_the_paused_profile_updates_nothing = function()
        local world, controller, saved = start_after_login()
        world.minimize_window(42)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "deactivate", profile = "1" }
        )
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, nil)
        expect_profile_1_as_saved(controller, saved)
    end,

    a_restore_that_the_watchdog_stops_before_the_concealment_keeps_the_pause = function()
        local world, controller, saved = start_after_login({
            timing = (function()
                local timing = require("tests.fake_worlds").create_default_timing()
                timing.busy_watchdog_seconds = 0.5
                return timing
            end)(),
        })
        world.windows[41].space_id = 64
        world.windows[41].is_unseen = true
        world.move_delay_seconds = 5
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.is_active_profile_paused, true)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        expect.equal(controller.state.is_active_profile_paused, true)
        expect.equal(
            profile_state.find_arrangement(controller.state, 1, "built-in"),
            profile_state.find_arrangement(profile_state.decode(saved), 1, "built-in")
        )
    end,

    the_profile_shortcut_after_the_restore_deactivates_as_before = function()
        local world, controller = start_after_login()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        expect.equal(controller.state.active_profile_number, nil)
    end,

    saving_the_arrangement_during_the_pause_records_the_windows_and_ends_the_pause = function()
        local routes = {
            function(world)
                controller_world
                    .find_menu_item(world, "Save arrangement now and end the pause")
                    .fn()
            end,
            function(world)
                world.url_handlers["desktop-manager"]("desktop-manager", { action = "save" })
            end,
        }
        for _, route in ipairs(routes) do
            local world, controller = start_after_login()
            world.minimize_window(42)
            route(world)
            expect.equal(controller.state.is_active_profile_paused, false)
            expect.equal(controller_world.recorded_sight(controller, 1, 42), "out of sight")
        end
    end,

    saving_the_arrangement_while_the_monitors_settle_keeps_the_pause = function()
        local world, controller, saved = start_after_login()
        world.minimize_window(42)
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        controller_world.find_menu_item(world, "Save arrangement now and end the pause").fn()
        expect.equal(controller.state.is_active_profile_paused, true)
        world.advance(controller_world.SETTLE_SECONDS)
        expect_profile_1_as_saved(controller, saved)
    end,

    clearing_the_paused_profile_ends_the_pause_and_clearing_another_keeps_it = function()
        local first_world = controller_world.start_world()
        first_world.hotkeys["2"]()
        first_world.advance(controller_world.SETTLE_SECONDS)
        first_world.hotkeys["1"]()
        first_world.advance(controller_world.SETTLE_SECONDS)
        local world, controller = controller_world.start_world(nil, first_world.saved_json, {
            seconds_since_macos_start = SECONDS_AFTER_LOGIN,
            macos_start_time = MACOS_START_TIME_AFTER_RESTART,
        })
        world.alert_button = "Clear"
        world.hotkey_by_shortcut["ctrl+alt+cmd 2"]()
        expect.equal(controller.state.is_active_profile_paused, true)
        world.hotkey_by_shortcut["ctrl+alt+cmd 1"]()
        expect.equal(controller.state.is_active_profile_paused, false)
        expect.equal(
            world.alerts[#world.alerts],
            "Profile 1 is cleared and records the windows from now on"
        )
    end,

    the_numbers_during_the_pause_follow_the_record_and_the_choices_of_the_user = function()
        local world, controller, saved = start_after_login()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "1", app = "Microsoft Word" }
        )
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "release-app-number", number = "1" }
        )
        expect.equal(
            profile_state.profile_or_default(controller.state, 1).app_numbers,
            saved.profiles["1"].app_numbers
        )
        expect.equal(world.saved_json.profiles["1"].app_numbers, saved.profiles["1"].app_numbers)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "3", app = "Microsoft Word" }
        )
        local chosen = profile_state.profile_or_default(controller.state, 1).app_numbers
        expect.equal(chosen[#chosen].number, 3)
        expect.equal(chosen[#chosen].is_chosen_by_user, true)
        world.close_window(41)
        world.app_hotkeys["0"]()
        expect.equal(
            profile_state.profile_or_default(controller.state, 1).app_numbers,
            saved.profiles["1"].app_numbers
        )
    end,

    the_numbers_during_the_pause_stay_under_monitors_that_the_profile_did_not_record = function()
        local world, controller, saved = start_after_login()
        world.connect_screen(controller_world.DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "release-app-number", number = "3" }
        )
        expect.equal(
            profile_state.profile_or_default(controller.state, 1).app_numbers,
            saved.profiles["1"].app_numbers
        )
        world.app_hotkeys["0"]()
        expect.equal(
            profile_state.profile_or_default(controller.state, 1).app_numbers,
            saved.profiles["1"].app_numbers
        )
        expect.equal(controller.state.is_active_profile_paused, true)
    end,

    the_menu_bar_item_and_the_diagnostics_show_the_pause = function()
        local world = start_after_login()
        expect.equal(world.menubar_title, "◧ 1 paused")
        expect.equal(
            world.menubar_tooltip,
            "Profile 1 is paused, and activating it restores its layout"
        )
        expect.equal(controller_world.find_menu_item(world, "1  Profile 1").state, "mixed")
        expect.equal(controller_world.find_menu_item(world, "2  Profile 2").state, "off")
        local printed, original_print = {}, print
        _G.print = function(text)
            table.insert(printed, text)
        end
        controller_world.find_menu_item(world, "Print diagnostics to the console").fn()
        _G.print = original_print
        expect.present(
            table.concat(printed, "\n"):find("\nactive profile: 1, paused\n", 1, true),
            "the line of the paused profile"
        )
        world.url_handlers["desktop-manager"]("desktop-manager", { action = "save" })
        expect.equal(world.menubar_title, "◧ 1")
        expect.equal(world.menubar_tooltip, "Profile 1")
        expect.equal(controller_world.find_menu_item(world, "1  Profile 1").state, "on")
    end,
}
