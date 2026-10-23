local app_pool = require("desktop_manager.core.app_pool")
local expect = require("tests.expect")

local FIREFOX = { bundle_id = "org.mozilla.firefox", app_name = "Firefox" }
local SLACK = { bundle_id = "com.tinyspeck.slackmacgap", app_name = "Slack" }

return {
    a_new_pool_manages_every_application = function()
        local pool = app_pool.new()
        expect.equal(app_pool.holds_every_application(pool), true)
        expect.equal(app_pool.is_managed(pool, FIREFOX.bundle_id), true)
    end,

    the_skip_mode_manages_every_application_but_the_ticked_ones = function()
        local pool = app_pool.with_listed(app_pool.new(), SLACK.bundle_id, SLACK.app_name, true)
        expect.equal(app_pool.is_managed(pool, SLACK.bundle_id), false)
        expect.equal(app_pool.is_managed(pool, FIREFOX.bundle_id), true)
        expect.equal(app_pool.holds_every_application(pool), false)
    end,

    the_manage_mode_manages_the_ticked_applications_alone = function()
        local pool = app_pool.with_mode(app_pool.new(), app_pool.MANAGE_LISTED)
        expect.equal(app_pool.is_managed(pool, FIREFOX.bundle_id), false)
        pool = app_pool.with_listed(pool, FIREFOX.bundle_id, FIREFOX.app_name, true)
        expect.equal(app_pool.is_managed(pool, FIREFOX.bundle_id), true)
        expect.equal(app_pool.is_managed(pool, SLACK.bundle_id), false)
    end,

    each_mode_keeps_its_own_ticks = function()
        local pool = app_pool.with_listed(app_pool.new(), SLACK.bundle_id, SLACK.app_name, true)
        pool = app_pool.with_mode(pool, app_pool.MANAGE_LISTED)
        pool = app_pool.with_listed(pool, FIREFOX.bundle_id, FIREFOX.app_name, true)
        expect.equal(pool.skip_listed, { SLACK })
        expect.equal(pool.manage_listed, { FIREFOX })
        pool = app_pool.with_mode(pool, app_pool.SKIP_LISTED)
        expect.equal(app_pool.is_managed(pool, SLACK.bundle_id), false)
    end,

    ticking_twice_lists_once_and_unticking_removes = function()
        local pool = app_pool.with_listed(app_pool.new(), SLACK.bundle_id, SLACK.app_name, true)
        pool = app_pool.with_listed(pool, SLACK.bundle_id, SLACK.app_name, true)
        expect.equal(pool.skip_listed, { SLACK })
        pool = app_pool.with_listed(pool, SLACK.bundle_id, SLACK.app_name, false)
        expect.equal(pool.skip_listed, {})
    end,

    keep_managed_drops_the_items_of_other_applications = function()
        local pool = app_pool.with_listed(app_pool.new(), SLACK.bundle_id, SLACK.app_name, true)
        local records = { { bundle_id = FIREFOX.bundle_id }, { bundle_id = SLACK.bundle_id } }
        expect.equal(app_pool.keep_managed(pool, records), { { bundle_id = FIREFOX.bundle_id } })
        expect.equal(app_pool.keep_managed(app_pool.new(), records), records)
        local windows = { { app = FIREFOX.bundle_id }, { app = SLACK.bundle_id } }
        expect.equal(
            app_pool.keep_managed_by(pool, windows, function(window)
                return window.app
            end),
            { { app = FIREFOX.bundle_id } }
        )
        local arrangement = { monitor_configuration_key = "built-in", windows = records }
        expect.equal(app_pool.keep_managed_records(pool, arrangement), {
            monitor_configuration_key = "built-in",
            windows = { { bundle_id = FIREFOX.bundle_id } },
        })
        expect.equal(#arrangement.windows, 2)
    end,

    choices_list_each_application_once_by_name_with_the_ticks_of_the_mode = function()
        local pool = app_pool.with_listed(app_pool.new(), SLACK.bundle_id, SLACK.app_name, true)
        expect.equal(app_pool.list_choices(pool, { FIREFOX, SLACK }), {
            { bundle_id = FIREFOX.bundle_id, app_name = "Firefox", is_listed = false },
            { bundle_id = SLACK.bundle_id, app_name = "Slack", is_listed = true },
        })
        local manage_pool = app_pool.with_mode(pool, app_pool.MANAGE_LISTED)
        expect.equal(app_pool.list_choices(manage_pool, { SLACK })[1].is_listed, false)
    end,

    describe_names_the_mode_and_the_ticked_applications = function()
        local pool = app_pool.with_listed(app_pool.new(), SLACK.bundle_id, SLACK.app_name, true)
        expect.equal(app_pool.describe(pool), "every application except Slack")
        expect.equal(
            app_pool.describe(app_pool.with_mode(pool, app_pool.MANAGE_LISTED)),
            "only none"
        )
    end,

    decode_reads_the_pool_and_rejects_an_unknown_mode = function()
        local pool = app_pool.with_listed(app_pool.new(), SLACK.bundle_id, SLACK.app_name, true)
        expect.equal(app_pool.decode(pool, nil), pool)
        expect.equal(app_pool.decode({ mode = "other" }, nil), app_pool.new())
    end,

    decode_turns_the_managed_applications_of_an_older_state_into_the_manage_mode = function()
        local pool = app_pool.decode(nil, { FIREFOX })
        expect.equal(pool.mode, app_pool.MANAGE_LISTED)
        expect.equal(pool.manage_listed, { FIREFOX })
        expect.equal(app_pool.decode(nil, nil), app_pool.new())
    end,
}
