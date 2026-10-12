local expect = require("tests.expect")
local tiling_position = require("window_tiling.core.tiling_position")

local USABLE_FRAME = { x = 0, y = 25, w = 1440, h = 875 }

return {
    fill_takes_the_whole_usable_frame = function()
        expect.equal(
            tiling_position.compute_frame(tiling_position.FILL, USABLE_FRAME),
            USABLE_FRAME
        )
    end,

    the_left_and_right_halves_split_the_width = function()
        expect.equal(
            tiling_position.compute_frame(tiling_position.LEFT_HALF, USABLE_FRAME),
            { x = 0, y = 25, w = 720, h = 875 }
        )
        expect.equal(
            tiling_position.compute_frame(tiling_position.RIGHT_HALF, USABLE_FRAME),
            { x = 720, y = 25, w = 720, h = 875 }
        )
    end,

    the_top_and_bottom_halves_share_their_middle_edge = function()
        local top = tiling_position.compute_frame(tiling_position.TOP_HALF, USABLE_FRAME)
        local bottom = tiling_position.compute_frame(tiling_position.BOTTOM_HALF, USABLE_FRAME)
        expect.equal(top, { x = 0, y = 25, w = 1440, h = 438 })
        expect.equal(bottom, { x = 0, y = 463, w = 1440, h = 437 })
    end,

    a_screen_to_the_right_offsets_the_frame = function()
        local external_frame = { x = 1440, y = -200, w = 2560, h = 1415 }
        expect.equal(
            tiling_position.compute_frame(tiling_position.RIGHT_HALF, external_frame),
            { x = 2720, y = -200, w = 1280, h = 1415 }
        )
    end,

    an_unknown_position_raises_an_error = function()
        local is_successful, message =
            pcall(tiling_position.compute_frame, "middle-third", USABLE_FRAME)
        expect.equal(is_successful, false)
        expect.equal(message:match('the tiling position "middle%-third" is unknown') ~= nil, true)
    end,

    parse_accepts_each_position = function()
        for _, position in ipairs(tiling_position.POSITIONS) do
            expect.equal(tiling_position.parse(position), position)
        end
    end,

    parse_rejects_a_missing_or_unknown_position = function()
        local position, message = tiling_position.parse(nil)
        expect.equal(position, nil)
        expect.equal(
            message,
            'the tiling position "nil" is not one of fill, left-half, right-half, top-half,'
                .. " bottom-half"
        )
        expect.equal(tiling_position.parse("center"), nil)
    end,
}
