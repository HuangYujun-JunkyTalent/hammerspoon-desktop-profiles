local default_settings = require("desktop_manager.default_settings")
local expect = require("tests.expect")
local highlight_colors = require("desktop_manager.core.highlight_colors")
local list_layout = require("desktop_manager.core.list_layout")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local settings_check = require("desktop_manager.core.settings_check")

return {
    the_default_settings_pass_and_the_copy_holds_the_completed_colors = function()
        local settings = default_settings.create("/fake/state.json")
        settings.search_highlight_colors = { hover = { white = 0.5 } }
        local checked, message = settings_check.check(settings)
        if not checked then
            error(message, 0)
        end
        expect.equal(checked.search_highlight_colors.hover, { white = 0.5 })
        expect.equal(
            checked.search_highlight_colors.selection,
            highlight_colors.defaults().selection
        )
        expect.equal(checked.list_layout, list_layout.COLUMNS)
        expect.equal(checked.timing, settings.timing)
        expect.equal(settings.search_highlight_colors, { hover = { white = 0.5 } })
    end,

    a_value_outside_a_closed_set_names_the_setting_and_the_value = function()
        ---@type table the settings with a value outside the closed set of the setting
        local settings = default_settings.create("/fake/state.json")
        settings.list_layout = "grid"
        expect.equal(
            { settings_check.check(settings) },
            { nil, 'the setting list_layout is "grid", which names no layout' }
        )
    end,

    the_message_names_the_faulty_setting_that_is_checked_first = function()
        ---@type table the settings with a value outside the closed set of the setting
        local settings = default_settings.create("/fake/state.json")
        settings.concealment_method = "close"
        settings.preview_size = { w = 2, h = 0.1 }
        expect.equal({ settings_check.check(settings) }, {
            nil,
            "the setting preview_size must give w and h as fractions of the screen, above 0"
                .. " and at most 1",
        })
    end,

    an_old_value_of_missing_window_policy_gives_way_to_its_new_value_with_a_line = function()
        local settings = default_settings.create("/fake/state.json")
        settings.missing_window_policy = "open_new_window"
        local replaced, lines = settings_check.replace_old_values(settings)
        expect.equal(replaced.missing_window_policy, missing_window_policy.MATCH_ID_ALONE)
        expect.equal(lines, {
            'the setting missing_window_policy is "open_new_window", the old name of'
                .. ' "match_id_alone"',
        })
        expect.equal(settings.missing_window_policy, "open_new_window")
        settings.missing_window_policy = "match_title_or_open_new_window"
        replaced, lines = settings_check.replace_old_values(settings)
        expect.equal(replaced.missing_window_policy, missing_window_policy.MATCH_TITLE)
        expect.equal(lines, {
            'the setting missing_window_policy is "match_title_or_open_new_window", the old name'
                .. ' of "match_title"',
        })
    end,

    the_current_values_give_no_line = function()
        local settings = default_settings.create("/fake/state.json")
        local replaced, lines = settings_check.replace_old_values(settings)
        expect.equal(replaced, settings)
        expect.equal(lines, {})
    end,
}
