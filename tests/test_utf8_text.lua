local expect = require("tests.expect")
local utf8_text = require("desktop_manager.core.utf8_text")

return {
    a_text_counts_its_characters_and_falls_back_to_bytes_when_it_is_no_valid_utf8 = function()
        local invalid = "ab\255c"
        expect.equal(utf8_text.split_characters("Ünï—x"), { "Ü", "n", "ï", "—", "x" })
        expect.equal(utf8_text.split_characters(invalid), { "a", "b", "\255", "c" })
        expect.equal(utf8_text.count_characters("Ünï—x"), 5)
        expect.equal(utf8_text.count_characters(invalid), 4)
        expect.equal(utf8_text.shorten("Ünï—x", 5), "Ünï—x")
        expect.equal(utf8_text.shorten("Ünï—x", 4), "Ünï…")
        expect.equal(utf8_text.shorten(invalid, 3), "ab\255")
        expect.equal(utf8_text.remove_last_character("Ünï—"), "Ünï")
        expect.equal(utf8_text.remove_last_character("ab\255"), "ab")
        expect.equal(utf8_text.trim("  Writing \t"), "Writing")
        expect.equal(utf8_text.trim("   "), "")
    end,
}
