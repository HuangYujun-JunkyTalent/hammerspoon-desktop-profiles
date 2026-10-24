local expect = require("tests.expect")
local preview_pacing = require("desktop_manager.core.preview_pacing")

---@param actual number
---@param expected number
local function expect_seconds(actual, expected)
    if math.abs(actual - expected) > 1e-9 then
        error(string.format("expected %g seconds, got %g", expected, actual), 2)
    end
end

return {
    the_first_preview_waits_for_the_drawing_of_the_panel = function()
        expect_seconds(preview_pacing.seconds_until_next_preview(10, 10, nil), 0.05)
        expect_seconds(preview_pacing.seconds_until_next_preview(10.03, 10, nil), 0.02)
    end,

    a_preview_waits_for_the_quiet_time_after_the_last_input = function()
        expect_seconds(preview_pacing.seconds_until_next_preview(10.06, 10, 10.04), 0.13)
        expect_seconds(preview_pacing.seconds_until_next_preview(10.01, 10, 10.01), 0.15)
    end,

    a_preview_starts_at_once_after_the_drawing_and_the_quiet_time = function()
        expect.equal(preview_pacing.seconds_until_next_preview(10.3, 10, 10.1), 0)
        expect.equal(preview_pacing.seconds_until_next_preview(10.3, 10, nil), 0)
    end,
}
