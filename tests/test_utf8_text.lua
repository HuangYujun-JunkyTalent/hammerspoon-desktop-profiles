local expect = require("tests.expect")
local utf8_text = require("desktop_manager.core.utf8_text")

return {
    splitting_and_counting_fall_back_to_bytes_for_a_text_that_is_no_valid_utf8 = function()
        local invalid = "ab\255c"
        expect.equal(utf8_text.split_characters("Ünï—x"), { "Ü", "n", "ï", "—", "x" })
        expect.equal(utf8_text.split_characters(invalid), { "a", "b", "\255", "c" })
        expect.equal(utf8_text.count_characters("Ünï—x"), 5)
        expect.equal(utf8_text.count_characters(invalid), 4)
    end,

    shorten_ends_a_long_text_in_an_ellipsis_and_cuts_an_invalid_text_by_bytes = function()
        expect.equal(utf8_text.shorten("Ünï—x", 5), "Ünï—x")
        expect.equal(utf8_text.shorten("Ünï—x", 4), "Ünï…")
        expect.equal(utf8_text.shorten("ab\255c", 3), "ab\255")
    end,

    remove_last_character_removes_one_character_of_a_valid_or_an_invalid_text = function()
        expect.equal(utf8_text.remove_last_character("Ünï—"), "Ünï")
        expect.equal(utf8_text.remove_last_character("ab\255"), "ab")
    end,

    trim_removes_the_blanks_at_both_ends = function()
        expect.equal(utf8_text.trim("  Writing \t"), "Writing")
        expect.equal(utf8_text.trim("   "), "")
    end,
}
