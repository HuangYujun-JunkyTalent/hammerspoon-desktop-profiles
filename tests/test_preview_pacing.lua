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
    the_previews_wait_for_the_drawing_of_the_panel = function()
        expect_seconds(preview_pacing.seconds_until_previews_start(10, 10), 0.05)
        expect_seconds(preview_pacing.seconds_until_previews_start(10.03, 10), 0.02)
    end,

    the_previews_start_at_once_after_the_drawing = function()
        expect_seconds(preview_pacing.seconds_until_previews_start(10.05, 10), 0)
        expect.equal(preview_pacing.seconds_until_previews_start(10.3, 10), 0)
    end,
}
