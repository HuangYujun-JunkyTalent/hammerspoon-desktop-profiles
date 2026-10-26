local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local list_layout = require("desktop_manager.core.list_layout")
local profile_state = require("desktop_manager.core.profile_state")
local unmatched_window_action = require("desktop_manager.core.unmatched_window_action")

---@param world table
---@return boolean whether the menu bar item has an item with the title
local function has_menu_item(world, title)
    return (pcall(controller_world.find_menu_item, world, title))
end

return {
    the_menu_opens_the_settings_in_place_of_the_colors_and_the_monitor_matching = function()
        local world, controller = controller_world.start_world()
        expect.equal(has_menu_item(world, "Search colors…"), false)
        expect.equal(has_menu_item(world, "Same monitor configuration by"), false)
        controller_world.find_menu_item(world, "Settings…").fn()
        local model = expect.present(controller.settings_window, "the window Settings").model
        expect.equal(model.values.unmatched_window_action, unmatched_window_action.OPEN_NEW_WINDOW)
        expect.equal(model.values.monitor_matching, "by_count")
        expect.equal(model.defaults.preview_size, { w = 0.1, h = 0.1 })
        expect.equal(model.sections[1].title, "Switching profiles")
        world.post_to_webview("settings", { kind = "done" })
        expect.equal(controller.settings_window, nil)
        world.url_handlers["desktop-manager"]("desktop-manager", { action = "open-settings" })
        expect.present(controller.settings_window, "the window Settings")
    end,

    forget_from_the_window_holds_at_the_next_switch_until_default_brings_back_the_file = function()
        local world, controller = controller_world.start_world()
        controller_world.find_menu_item(world, "Settings…").fn()
        world.post_to_webview(
            "settings",
            { kind = "set", name = "unmatched_window_action", value = "forget" }
        )
        expect.equal(world.saved_json.setting_overrides, { unmatched_window_action = "forget" })
        local window = controller.settings_window --[[@as SettingsWindow]]
        expect.equal(window.model.values.unmatched_window_action, "forget")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(41)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.find_window_titled(world, "Start Page"), nil)
        expect.equal(controller_world.recorded_sight(controller, 1, 41), nil)
        world.post_to_webview("settings", { kind = "reset", name = "unmatched_window_action" })
        expect.equal(world.saved_json.setting_overrides, {})
        expect.equal(
            controller.settings.unmatched_window_action,
            unmatched_window_action.OPEN_NEW_WINDOW
        )
    end,

    a_value_that_the_window_does_not_offer_changes_nothing = function()
        local world, controller = controller_world.start_world()
        controller_world.find_menu_item(world, "Settings…").fn()
        world.post_to_webview("settings", { kind = "set", name = "list_layout", value = "grid" })
        world.post_to_webview("settings", { kind = "set", name = "profile_count", value = 3 })
        expect.equal(controller.settings.list_layout, list_layout.COLUMNS)
        expect.equal(controller.state.setting_overrides, {})
        world.post_to_webview("settings", { kind = "set", name = "title_line_count", value = 3.0 })
        expect.equal(math.type(controller.settings.title_line_count), "integer")
    end,

    the_monitor_matching_of_the_window_is_the_one_of_the_state = function()
        local world, controller = controller_world.start_world()
        controller_world.find_menu_item(world, "Settings…").fn()
        world.post_to_webview(
            "settings",
            { kind = "set", name = "monitor_matching", value = "by_identity" }
        )
        expect.equal(controller.state.monitor_matching, "by_identity")
        expect.equal(
            world.alerts[#world.alerts],
            "Same monitor configuration by name of each external monitor"
        )
        world.post_to_webview("settings", { kind = "reset", name = "monitor_matching" })
        expect.equal(controller.state.monitor_matching, "by_count")
        expect.equal(controller.state.setting_overrides, {})
    end,

    a_change_waits_while_a_switch_runs = function()
        local world, controller = controller_world.start_world()
        controller_world.find_menu_item(world, "Settings…").fn()
        controller.is_switch_or_restore_running = true
        world.post_to_webview(
            "settings",
            { kind = "set", name = "unmatched_window_action", value = "forget" }
        )
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        expect.equal(
            controller.settings.unmatched_window_action,
            unmatched_window_action.OPEN_NEW_WINDOW
        )
        local model = (controller.settings_window --[[@as SettingsWindow]]).model
        expect.equal(model.values.unmatched_window_action, unmatched_window_action.OPEN_NEW_WINDOW)
    end,

    a_saved_choice_holds_after_a_start_and_reaches_the_parts_that_hold_the_settings = function()
        local _, controller = controller_world.start_world(nil, {
            format_version = profile_state.FORMAT_VERSION,
            monitor_matching = "by_count",
            setting_overrides = { unmatched_window_action = "forget", list_layout = "rows" },
        })
        expect.equal(controller.settings.unmatched_window_action, unmatched_window_action.FORGET)
        expect.equal(controller.settings.list_layout, list_layout.ROWS)
        expect.equal(controller.preview_loader.settings, controller.settings)
        expect.equal(controller.base_settings.list_layout, list_layout.COLUMNS)
    end,
}
