local app_pool = require("desktop_manager.core.app_pool")
local app_pool_window = require("desktop_manager.macos.app_pool_window")
local expect = require("tests.expect")

return {
    the_page_checks_the_mode_and_the_ticked_applications = function()
        local pool = app_pool.with_mode(app_pool.new(), app_pool.MANAGE_LISTED)
        local page = app_pool_window.build_page(pool, {
            { bundle_id = "org.mozilla.firefox", app_name = "Firefox", is_listed = true },
            { bundle_id = "com.apple.Safari", app_name = "Safari", is_listed = false },
        })
        expect.present(
            page:find("value='manage_listed' checked", 1, true),
            "the mode manage_listed checked"
        )
        expect.equal(page:find("value='skip_listed' checked", 1, true), nil)
        expect.present(
            page:find('data-app-name="Firefox" checked> Firefox', 1, true),
            "Firefox ticked in the list"
        )
        expect.present(
            page:find('data-app-name="Safari"> Safari', 1, true),
            "Safari unticked in the list"
        )
    end,

    the_page_escapes_the_names_of_applications = function()
        local page = app_pool_window.build_page(app_pool.new(), {
            { bundle_id = "com.example.tool", app_name = 'A <b>"Tool"</b>', is_listed = false },
        })
        expect.equal(page:find("<b>", 1, true), nil)
        expect.present(
            page:find("A &lt;b&gt;&quot;Tool&quot;&lt;/b&gt;", 1, true),
            "the escaped name of the application"
        )
    end,
}
