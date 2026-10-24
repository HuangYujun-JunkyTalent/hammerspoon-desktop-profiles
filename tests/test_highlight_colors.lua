local expect = require("tests.expect")
local highlight_colors = require("desktop_manager.core.highlight_colors")
local profile_state = require("desktop_manager.core.profile_state")

return {
    each_form_of_a_color_reads_as_hex_and_alpha = function()
        expect.equal({
            highlight_colors.to_hex_and_alpha({
                red = 0.2,
                green = 0.45,
                blue = 0.95,
                alpha = 0.95,
            }),
        }, { "#3373F2", 0.95 })
        expect.equal(
            { highlight_colors.to_hex_and_alpha({ white = 1, alpha = 0.16 }) },
            { "#FFFFFF", 0.16 }
        )
        expect.equal({ highlight_colors.to_hex_and_alpha({ hex = "#2e8b57" }) }, { "#2E8B57", 1 })
    end,

    the_chosen_colors_cover_the_setting_and_a_bad_one_is_dropped = function()
        local chosen = highlight_colors.decode({
            selection = { hex = "#2E8B57", alpha = 0.9 },
            hover = { hex = "green" },
            other = { white = 1 },
        })
        expect.equal(chosen, { selection = { hex = "#2E8B57", alpha = 0.9 } })
        local colors = highlight_colors.apply(highlight_colors.defaults(), chosen)
        expect.equal(colors.selection, { hex = "#2E8B57", alpha = 0.9 })
        expect.equal(colors.hover, highlight_colors.defaults().hover)
    end,

    the_state_keeps_the_chosen_colors = function()
        local state = profile_state.with_highlight_colors(
            profile_state.new_state("by_count"),
            { weak_match = { hex = "#FFCC00", alpha = 0.5 } }
        )
        local decoded = expect.present(profile_state.decode(state), "the decoded state")
        expect.equal(decoded.highlight_colors, { weak_match = { hex = "#FFCC00", alpha = 0.5 } })
        expect.equal(#highlight_colors.PRESETS, 4)
    end,
}
