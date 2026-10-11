---How the list of numbered applications arranges the applications and their windows.
---`ROWS` stacks each application and its windows in one column of lines.
---`COLUMNS` gives each application a column, with its windows stacked downward.
---`COLUMNS_PER_DISPLAY` groups the columns by display, so an application has a column for each
---display that holds one of its windows.
local list_layout = {
    ROWS = "rows",
    COLUMNS = "columns",
    COLUMNS_PER_DISPLAY = "columns_per_display",
}

local VALID = {
    [list_layout.ROWS] = true,
    [list_layout.COLUMNS] = true,
    [list_layout.COLUMNS_PER_DISPLAY] = true,
}

---@param value any
---@return boolean
function list_layout.is_valid(value)
    return VALID[value] == true
end

return list_layout
