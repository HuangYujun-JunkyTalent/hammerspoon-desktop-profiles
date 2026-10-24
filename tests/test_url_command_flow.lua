local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local profile_state = require("desktop_manager.core.profile_state")

return {
    a_url_renames_a_profile = function()
        local world, controller = controller_world.start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "rename", profile = "4", name = "Writing" }
        )
        expect.equal(profile_state.profile_or_default(controller.state, 4).name, "Writing")
    end,

    a_url_deactivates_a_named_profile_only_while_it_is_active = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "deactivate", profile = "2" }
        )
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.alerts[#world.alerts], "Profile 2 is not active")
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "deactivate", profile = "1" }
        )
        expect.equal(controller.state.active_profile_number, nil)
    end,

    a_url_activates_a_profile_and_deactivates_it_while_it_is_active = function()
        local world, controller = controller_world.start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "toggle", profile = "2" }
        )
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "toggle", profile = "2" }
        )
        expect.equal(controller.state.active_profile_number, nil)
        expect.equal(world.alerts[#world.alerts], "No desktop profile")
    end,

    a_url_changes_when_monitor_configurations_are_the_same = function()
        local world, controller = controller_world.start_world()
        expect.equal(controller.state.monitor_matching, "by_count")
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "cycle-monitor-matching" }
        )
        expect.equal(controller.state.monitor_matching, "by_identity")
        expect.equal(
            world.alerts[#world.alerts],
            "Same monitor configuration by name of each external monitor"
        )
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "cycle-monitor-matching" }
        )
        expect.equal(controller.state.monitor_matching, "by_count")
    end,

    a_bad_url_is_reported = function()
        local world = controller_world.start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "activate", profile = "11" }
        )
        expect.equal(world.notifications, { 'the profile "11" is not a number from 1 to 9' })
    end,
}
