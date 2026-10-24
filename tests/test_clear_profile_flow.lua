local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local profile_state = require("desktop_manager.core.profile_state")

return {
    the_menu_offers_each_recorded_profile_to_clear = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local clear_items = controller_world.find_menu_item(world, "Clear profile").menu
        expect.equal(clear_items[1].disabled, false)
        expect.equal(clear_items[2].disabled, true)
    end,

    clearing_a_profile_after_the_confirmation_removes_its_layouts = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "clear", profile = "1" }
        )
        expect.equal(profile_state.has_arrangements(controller.state, 1), true)
        world.alert_button = "Clear"
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "clear", profile = "1" }
        )
        expect.equal(profile_state.has_arrangements(controller.state, 1), false)
        expect.equal(world.alerts[#world.alerts], "Profile 1 is cleared")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.alerts[#world.alerts], "Profile 1")
        expect.equal(world.windows[42].is_minimized, true)
    end,

    control_option_command_with_the_number_clears_a_profile_after_the_confirmation = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut["ctrl+alt+cmd 1"]()
        expect.equal(profile_state.has_arrangements(controller.state, 1), true)
        world.alert_button = "Clear"
        world.hotkey_by_shortcut["ctrl+alt+cmd 1"]()
        expect.equal(profile_state.has_arrangements(controller.state, 1), false)
        expect.equal(
            world.alerts[#world.alerts],
            "Profile 1 is cleared and records the windows from now on"
        )
    end,
}
