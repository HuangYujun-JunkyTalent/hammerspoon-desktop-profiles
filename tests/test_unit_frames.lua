local expect = require("tests.expect")
local unit_frames = require("desktop_manager.core.unit_frames")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }

return {
    to_unit_frame_is_relative_to_the_screen = function()
        local unit = unit_frames.to_unit_frame({ x = 720, y = 25, w = 720, h = 875 }, BUILTIN_FRAME)
        expect.equal(unit, { x = 0.5, y = 0, w = 0.5, h = 1 })
    end,

    from_unit_frame_reaches_past_the_screen_like_the_window = function()
        local unit = unit_frames.to_unit_frame({ x = 0, y = 10, w = 1440, h = 900 }, BUILTIN_FRAME)
        expect.equal(unit.y < 0 and unit.h > 1, true)
        expect.equal(
            unit_frames.from_unit_frame(unit, BUILTIN_FRAME),
            { x = 0, y = 10, w = 1440, h = 900 }
        )
    end,

    from_unit_frame_gives_no_frame_without_area = function()
        expect.equal(
            unit_frames.from_unit_frame({ x = 0.2778, y = 1, w = 0, h = 0 }, BUILTIN_FRAME),
            nil
        )
    end,
}
