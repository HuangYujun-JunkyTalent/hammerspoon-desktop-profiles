---The characters of a text, read as UTF-8, and read as bytes when the text is no valid UTF-8.
local utf8_text = {}

local ELLIPSIS = "…"

---@param text string
---@return string[] the characters of the text, or its bytes when it is no valid UTF-8
function utf8_text.split_characters(text)
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

---@param text string
---@return integer the characters of the text
function utf8_text.count_characters(text)
    return #utf8_text.split_characters(text)
end

---@param text string
---@param max_length integer the most characters that the text keeps, the ellipsis included
---@return string
function utf8_text.shorten(text, max_length)
    local is_valid, length = pcall(utf8.len, text)
    if not is_valid or not length then
        return text:sub(1, max_length)
    end
    if length <= max_length then
        return text
    end
    return text:sub(1, utf8.offset(text, max_length) - 1) .. ELLIPSIS
end

---@param text string
---@return string the text without its last character
function utf8_text.remove_last_character(text)
    local is_valid, start = pcall(utf8.offset, text, -1)
    if not is_valid or not start then
        return text:sub(1, -2)
    end
    return text:sub(1, start - 1)
end

---@param text string
---@return string the text without the blanks at its start and at its end
function utf8_text.trim(text)
    return text:match("^%s*(.-)%s*$")
end

return utf8_text
