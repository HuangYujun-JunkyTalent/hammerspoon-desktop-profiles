---How the list of numbered applications chooses its sizes on the screen in front.
---`FILL_SCREEN` grows or shrinks the previews and the fonts until the list fills the screen.
---`FIXED` keeps the sizes of the settings, and shrinks them only to fit within the screen.
local list_sizing = {
    FILL_SCREEN = "fill_screen",
    FIXED = "fixed",
}

local VALID = {
    [list_sizing.FILL_SCREEN] = true,
    [list_sizing.FIXED] = true,
}

---@param value any
---@return boolean
function list_sizing.is_valid(value)
    return VALID[value] == true
end

return list_sizing
