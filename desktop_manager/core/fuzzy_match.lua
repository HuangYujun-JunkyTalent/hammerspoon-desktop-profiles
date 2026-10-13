---Scores a search against texts, such as the name of an application and the title of a window.
---Each word of the search must appear in one of the texts as a subsequence that ignores the case
---of ASCII letters.
---A letter that follows the previous letter of the word, or that starts a word of the text, scores
---twice as much as a letter elsewhere, so the score of a word lies from 0.5 to 1.
---The levels split the scores into three, for the highlighting of the matches.
local fuzzy_match = {
    ---A score of 0.9 or more, as of a word that starts a word of the text with all its letters in a
    ---row, or that gives the first letters of the words of the text.
    STRONG = "strong",
    ---A score of 0.7 or more, as of a word whose letters stand in a row inside a word of the text.
    MEDIUM = "medium",
    ---A lower score, as of a word whose letters stand apart.
    WEAK = "weak",
}

local STRONG_SCORE = 0.9
local MEDIUM_SCORE = 0.7

---@param text string
---@return string[] the characters of the text, or its bytes when it is no valid UTF-8
local function split_characters(text)
    local characters = {}
    local is_valid = pcall(function()
        for _, code in utf8.codes(text) do
            table.insert(characters, utf8.char(code))
        end
    end)
    if is_valid then
        return characters
    end
    characters = {}
    for index = 1, #text do
        table.insert(characters, text:sub(index, index))
    end
    return characters
end

---@param character string|nil
---@return boolean whether the character belongs to a word, as a letter, a digit or a character
---beyond ASCII does
local function is_word_character(character)
    return character ~= nil and (#character > 1 or character:match("^%w$") ~= nil)
end

---@param previous string|nil
---@param character string
---@return boolean whether the character starts a word: after a space or a sign, at a capital
---after a small letter, or at a digit after a letter
local function is_word_start(previous, character)
    if not is_word_character(previous) then
        return true
    end
    if previous:match("^%l$") and character:match("^%u$") then
        return true
    end
    return previous:match("^%a$") ~= nil and character:match("^%d$") ~= nil
end

---@param query string
---@return string[] the words of the search, in lower case
function fuzzy_match.split_words(query)
    local words = {}
    for word in query:lower():gmatch("%S+") do
        table.insert(words, word)
    end
    return words
end

---The best score of the word in the text, over every way in which its letters appear in order.
---@param word string in lower case
---@param text string
---@return number|nil the score from 0.5 to 1, or nil when the letters do not appear in order
function fuzzy_match.score_word(word, text)
    local letters = split_characters(word)
    local original = split_characters(text)
    local lowered = split_characters(text:lower())
    if #letters == 0 or #lowered ~= #original then
        return nil
    end
    local starts = {}
    for index, character in ipairs(original) do
        starts[index] = is_word_start(original[index - 1], character)
    end
    -- The best score of the letters so far when the last of them falls on each position.
    local previous_scores = {}
    for letter_index, letter in ipairs(letters) do
        local scores, best_before = {}, nil
        for index, character in ipairs(lowered) do
            if character == letter then
                local start_bonus = starts[index] and 1 or 0
                if letter_index == 1 then
                    scores[index] = 1 + start_bonus
                else
                    local following = previous_scores[index - 1]
                    local candidate = best_before and best_before + 1 + start_bonus
                    if following and (not candidate or following + 2 > candidate) then
                        candidate = following + 2
                    end
                    scores[index] = candidate
                end
            end
            local previous = previous_scores[index]
            if previous and (not best_before or previous > best_before) then
                best_before = previous
            end
        end
        previous_scores = scores
    end
    local best = nil
    for _, score in pairs(previous_scores) do
        if not best or score > best then
            best = score
        end
    end
    return best and best / (2 * #letters)
end

---The mean of the scores of the words, each in the text where it scores best.
---@param query string
---@param texts string[]
---@return number|nil the score from 0.5 to 1, or nil when a word appears in none of the texts or
---the search has no word
function fuzzy_match.score(query, texts)
    local words = fuzzy_match.split_words(query)
    if #words == 0 then
        return nil
    end
    local total = 0
    for _, word in ipairs(words) do
        local best = nil
        for _, text in ipairs(texts) do
            local score = fuzzy_match.score_word(word, text)
            if score and (not best or score > best) then
                best = score
            end
        end
        if not best then
            return nil
        end
        total = total + best
    end
    return total / #words
end

---@param score number
---@return string a level of `fuzzy_match`
function fuzzy_match.level_of(score)
    if score >= STRONG_SCORE then
        return fuzzy_match.STRONG
    end
    if score >= MEDIUM_SCORE then
        return fuzzy_match.MEDIUM
    end
    return fuzzy_match.WEAK
end

return fuzzy_match
