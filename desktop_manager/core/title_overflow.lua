---What the list does with a title of a window that is longer than its space.
---`TRUNCATE` shortens the title to one line and ends it in an ellipsis.
---`WRAP` lets the title flow over several lines, up to the setting title_line_count.
---`SCROLL` scrolls the title of the selected window, and shortens the other titles.
local title_overflow = {
    TRUNCATE = "truncate",
    WRAP = "wrap",
    SCROLL = "scroll",
}

local VALID = {
    [title_overflow.TRUNCATE] = true,
    [title_overflow.WRAP] = true,
    [title_overflow.SCROLL] = true,
}

---@param value any
---@return boolean
function title_overflow.is_valid(value)
    return VALID[value] == true
end

return title_overflow
