local controller_world = require("tests.controller_world")
local expect = require("tests.expect")

return {
    a_window_of_an_unticked_application_stays_and_is_not_recorded = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, 41), "in sight")
        controller_world.open_app_pool_window(world)
        world.post_to_webview("appPool", {
            kind = "tick",
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            is_listed = true,
        })
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.recorded_sight(controller, 1, 41), nil)
        expect.equal(controller_world.recorded_sight(controller, 1, 42), "in sight")
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[42].is_minimized, true)
    end,

    the_window_of_the_pool_takes_several_ticks_and_a_change_of_mode = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        controller_world.open_app_pool_window(world)
        expect.equal(world.webview.is_visible, true)
        expect.present(
            world.webview.page:find('data-app-name="Safari"> Safari', 1, true),
            "Safari unticked in the list"
        )
        world.post_to_webview("appPool", { kind = "mode", mode = "manage_listed" })
        for _, application in ipairs({
            { "com.apple.Safari", "Safari" },
            { "com.microsoft.Word", "Microsoft Word" },
        }) do
            world.post_to_webview("appPool", {
                kind = "tick",
                bundle_id = application[1],
                app_name = application[2],
                is_listed = true,
            })
        end
        expect.equal(world.webview.is_visible, true)
        expect.equal(controller.state.app_pool.mode, "manage_listed")
        expect.equal(#controller.state.app_pool.manage_listed, 2)
        expect.equal(controller.state.app_pool.skip_listed, {})
        world.post_to_webview("appPool", { kind = "mode", mode = "skip_listed" })
        expect.equal(world.webview.page:find('data-app-name="Safari" checked', 1, true), nil)
        world.post_to_webview("appPool", { kind = "done" })
        expect.equal(world.webview.is_visible, false)
        expect.equal(controller.app_pool_window, nil)
    end,
}
