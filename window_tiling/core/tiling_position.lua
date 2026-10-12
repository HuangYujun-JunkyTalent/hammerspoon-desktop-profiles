---The positions that a tiling shortcut gives the focused window, as parts of the usable frame of
---its screen, which leaves out the menu bar and the Dock.
local tiling_position = {
    FILL = "fill",
    LEFT_HALF = "left-half",
    RIGHT_HALF = "right-half",
    TOP_HALF = "top-half",
    BOTTOM_HALF = "bottom-half",
}

---The part of the screen that each position takes, as fractions of its width and height.
local UNIT_RECT_BY_POSITION = {
    [tiling_position.FILL] = { x = 0, y = 0, w = 1, h = 1 },
    [tiling_position.LEFT_HALF] = { x = 0, y = 0, w = 0.5, h = 1 },
    [tiling_position.RIGHT_HALF] = { x = 0.5, y = 0, w = 0.5, h = 1 },
    [tiling_position.TOP_HALF] = { x = 0, y = 0, w = 1, h = 0.5 },
    [tiling_position.BOTTOM_HALF] = { x = 0, y = 0.5, w = 1, h = 0.5 },
}

---The positions in the order in which the README and the Asyar extension list them.
tiling_position.POSITIONS = {
    tiling_position.FILL,
    tiling_position.LEFT_HALF,
    tiling_position.RIGHT_HALF,
    tiling_position.TOP_HALF,
    tiling_position.BOTTOM_HALF,
}

---Reads the position that a URL such as `hammerspoon://window-tiling?position=left-half` names.
---@param text any the value of the parameter `position`
---@return string|nil position
---@return string|nil error_message
function tiling_position.parse(text)
    if UNIT_RECT_BY_POSITION[text] == nil then
        return nil,
            string.format(
                "the tiling position %q is not one of %s",
                tostring(text),
                table.concat(tiling_position.POSITIONS, ", ")
            )
    end
    return text, nil
end

---@param start number
---@param length number
---@param fraction number
---@return integer the point at the fraction of the length after the start, rounded to a point
local function round_edge(start, length, fraction)
    return math.floor(start + fraction * length + 0.5)
end

---Each edge is rounded on its own, so that two halves share their middle edge and leave no gap.
---@param position string a value of tiling_position
---@param screen_frame Rect the usable frame of the screen
---@return Rect
function tiling_position.compute_frame(position, screen_frame)
    local unit = UNIT_RECT_BY_POSITION[position]
    if not unit then
        error(string.format("the tiling position %q is unknown", tostring(position)), 2)
    end
    local left = round_edge(screen_frame.x, screen_frame.w, unit.x)
    local right = round_edge(screen_frame.x, screen_frame.w, unit.x + unit.w)
    local top = round_edge(screen_frame.y, screen_frame.h, unit.y)
    local bottom = round_edge(screen_frame.y, screen_frame.h, unit.y + unit.h)
    return { x = left, y = top, w = right - left, h = bottom - top }
end

return tiling_position
