local expect = require("tests.expect")
local fuzzy_match = require("desktop_manager.core.fuzzy_match")

return {
    a_word_at_the_start_of_the_text_with_its_letters_in_a_row_scores_one = function()
        expect.equal(fuzzy_match.score_word("fire", "Firefox"), 1)
        expect.equal(fuzzy_match.level_of(1), fuzzy_match.STRONG)
    end,

    letters_in_a_row_inside_a_word_score_less = function()
        expect.equal(fuzzy_match.score_word("fox", "Firefox"), 5 / 6)
        expect.equal(fuzzy_match.level_of(5 / 6), fuzzy_match.MEDIUM)
    end,

    letters_apart_score_least = function()
        expect.equal(fuzzy_match.score_word("frx", "Firefox"), 4 / 6)
        expect.equal(fuzzy_match.level_of(4 / 6), fuzzy_match.WEAK)
    end,

    the_first_letters_of_the_words_score_as_a_whole_word = function()
        expect.equal(fuzzy_match.score_word("gpr", "GitHub - pull requests"), 1)
        expect.equal(fuzzy_match.score_word("hub", "GitHub"), 1)
        expect.equal(fuzzy_match.score_word("2", "Draft2"), 1)
    end,

    the_best_of_the_ways_in_which_the_letters_appear_counts = function()
        expect.equal(fuzzy_match.score_word("ab", "axb ab"), 1)
    end,

    a_letter_missing_from_the_text_gives_no_score = function()
        expect.equal(fuzzy_match.score_word("xyz", "Firefox"), nil)
        expect.equal(fuzzy_match.score_word("of", "Firefox"), nil)
    end,

    characters_beyond_ascii_count_as_letters_of_a_word = function()
        expect.equal(fuzzy_match.score_word("中", "中文"), 1)
        expect.equal(fuzzy_match.score_word("文", "中文"), 0.5)
    end,

    the_search_ignores_case = function()
        expect.equal(fuzzy_match.score("INBOX", { "inbox" }), 1)
    end,

    every_word_must_appear_in_one_of_the_texts = function()
        local texts = { "Firefox", "GitHub - pull requests" }
        expect.equal(fuzzy_match.score("fire pull", texts), 1)
        expect.equal(fuzzy_match.score("fire zzz", texts), nil)
        expect.equal(fuzzy_match.score("fire fox", { "Firefox" }), (1 + 5 / 6) / 2)
    end,

    a_search_without_words_gives_no_score = function()
        expect.equal(fuzzy_match.score("   ", { "Firefox" }), nil)
    end,

    the_levels_start_at_their_scores = function()
        expect.equal(fuzzy_match.level_of(0.9), fuzzy_match.STRONG)
        expect.equal(fuzzy_match.level_of(0.7), fuzzy_match.MEDIUM)
        expect.equal(fuzzy_match.level_of(0.69), fuzzy_match.WEAK)
    end,
}
