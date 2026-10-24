---The positions that a tiling shortcut gives the focused window, as parts of the usable frame of
---its screen, which leaves out the menu bar and the Dock.
local tiling_position = {
    FILL = "fill",
    LEFT_HALF = "left-half",
    RIGHT_HALF = "right-half",
    TOP_HALF = "top-half",
    BOTTOM_HALF = "bottom-half",
}

---A position with the part of the screen that it takes and the action of its shortcut.
---@class PositionDescription
---@field position string a value of tiling_position
---@field unit_rect Rect the part of the screen, as fractions of its width and height
---@field title string the title of the action in the window of the shortcuts
---@field default_key string the key that the default shortcut holds with Control and Option

---The positions in the order in which the README and the Asyar extension list them.
---@type PositionDescription[]
tiling_position.DESCRIPTIONS = {
    {
        position = tiling_position.FILL,
        unit_rect = { x = 0, y = 0, w = 1, h = 1 },
        title = "Fill the screen with the front window",
        default_key = "return",
    },
    {
        position = tiling_position.LEFT_HALF,
        unit_rect = { x = 0, y = 0, w = 0.5, h = 1 },
        title = "Tile the front window to the left half",
        default_key = "left",
    },
    {
        position = tiling_position.RIGHT_HALF,
        unit_rect = { x = 0.5, y = 0, w = 0.5, h = 1 },
        title = "Tile the front window to the right half",
        default_key = "right",
    },
    {
        position = tiling_position.TOP_HALF,
        unit_rect = { x = 0, y = 0, w = 1, h = 0.5 },
        title = "Tile the front window to the top half",
        default_key = "up",
    },
    {
        position = tiling_position.BOTTOM_HALF,
        unit_rect = { x = 0, y = 0.5, w = 1, h = 0.5 },
        title = "Tile the front window to the bottom half",
        default_key = "down",
    },
}

---The values of tiling_position in the order of `DESCRIPTIONS`.
tiling_position.POSITIONS = {}
local UNIT_RECT_BY_POSITION = {}
for _, description in ipairs(tiling_position.DESCRIPTIONS) do
    table.insert(tiling_position.POSITIONS, description.position)
    UNIT_RECT_BY_POSITION[description.position] = description.unit_rect
end

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
