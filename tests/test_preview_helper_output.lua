local expect = require("tests.expect")
local preview_helper_output = require("desktop_manager.core.preview_helper_output")

local DATA_URL = "data:image/png;base64,iVBORw0KGgo="

return {
    a_line_over_two_chunks_comes_whole_with_the_second_chunk = function()
        local lines, rest = preview_helper_output.split_lines("", "41 0.021 data:image/png;")
        expect.equal(lines, {})
        expect.equal(rest, "41 0.021 data:image/png;")
        lines, rest = preview_helper_output.split_lines(rest, "base64,iVBORw0KGgo=\n")
        expect.equal(lines, { "41 0.021 " .. DATA_URL })
        expect.equal(rest, "")
    end,

    a_line_over_three_chunks_comes_whole_with_the_third_chunk = function()
        local rest = ""
        local lines_of_each_chunk = {}
        for _, chunk in ipairs({ "41 0.021 data:", "image/png;base64,", "iVBORw0KGgo=\n42" }) do
            local lines
            lines, rest = preview_helper_output.split_lines(rest, chunk)
            table.insert(lines_of_each_chunk, lines)
        end
        expect.equal(lines_of_each_chunk, { {}, {}, { "41 0.021 " .. DATA_URL } })
        expect.equal(rest, "42")
    end,

    two_lines_in_one_chunk_come_together = function()
        local lines, rest =
            preview_helper_output.split_lines("", "41 0.021 " .. DATA_URL .. "\n42 0.015 none\n")
        expect.equal(lines, { "41 0.021 " .. DATA_URL, "42 0.015 none" })
        expect.equal(rest, "")
        expect.equal(preview_helper_output.parse_line(lines[1]), {
            window_id = 41,
            capture_seconds = 0.021,
            data_url = DATA_URL,
        })
        expect.equal(
            preview_helper_output.parse_line(lines[2]),
            { window_id = 42, capture_seconds = 0.015 }
        )
    end,

    a_line_that_does_not_read_as_a_window_and_an_image_gives_nil = function()
        expect.equal(preview_helper_output.parse_line(""), nil)
        expect.equal(preview_helper_output.parse_line("41 0.021"), nil)
        expect.equal(preview_helper_output.parse_line("window 0.021 none"), nil)
        expect.equal(preview_helper_output.parse_line("41 slow none"), nil)
        expect.equal(preview_helper_output.parse_line("41 0.021 https://example.com/a.png"), nil)
    end,
}
