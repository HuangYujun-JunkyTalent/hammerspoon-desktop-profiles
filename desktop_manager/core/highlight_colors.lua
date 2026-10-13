---The colors behind the selected, hovered and matching items of the search of the windows.
---Each color is a table that hs.drawing.color takes: `red`, `green` and `blue`, or `white`, or
---`hex` such as "#3373F2", each with an optional `alpha` from 0 to 1.
local highlight_colors = {}

---@class HighlightColors
---@field selection table the selected window or application
---@field hover table the application under the mouse pointer
---@field strong_match table a window or application whose words match well
---@field medium_match table
---@field weak_match table

local NAMES = { "selection", "hover", "strong_match", "medium_match", "weak_match" }
local CHANNELS = { "red", "green", "blue", "white", "alpha" }

---@return HighlightColors
function highlight_colors.defaults()
    return {
        selection = { red = 0.2, green = 0.45, blue = 0.95, alpha = 0.95 },
        hover = { white = 1, alpha = 0.16 },
        strong_match = { red = 1, green = 0.72, blue = 0.18, alpha = 0.6 },
        medium_match = { red = 1, green = 0.72, blue = 0.18, alpha = 0.36 },
        weak_match = { red = 1, green = 0.72, blue = 0.18, alpha = 0.18 },
    }
end

---@param color any
---@return string|nil message why the value is no color
function highlight_colors.check(color)
    if type(color) ~= "table" then
        return "is no table"
    end
    for _, channel in ipairs(CHANNELS) do
        local value = color[channel]
        if value ~= nil and (type(value) ~= "number" or value < 0 or value > 1) then
            return string.format(
                "gives %s as %s, which is no number from 0 to 1",
                channel,
                tostring(value)
            )
        end
    end
    if
        color.hex ~= nil
        and not (type(color.hex) == "string" and color.hex:match("^#%x%x%x%x%x%x$"))
    then
        return string.format(
            'gives hex as %s, which is no color such as "#3373F2"',
            tostring(color.hex)
        )
    end
    if
        color.red == nil
        and color.green == nil
        and color.blue == nil
        and color.white == nil
        and color.hex == nil
    then
        return "names no red, green, blue, white or hex"
    end
    return nil
end

---Fills the colors that the setting leaves out with the defaults.
---@param colors table|nil the setting, with any of the five names
---@return HighlightColors|nil colors
---@return string|nil error_message
function highlight_colors.complete(colors)
    if colors == nil then
        return highlight_colors.defaults(), nil
    end
    if type(colors) ~= "table" then
        return nil, "the setting search_highlight_colors is no table"
    end
    local is_known = {}
    for _, name in ipairs(NAMES) do
        is_known[name] = true
    end
    for name in pairs(colors) do
        if not is_known[name] then
            return nil,
                string.format(
                    "the setting search_highlight_colors names %q, which is none of %s",
                    tostring(name),
                    table.concat(NAMES, ", ")
                )
        end
    end
    local completed = highlight_colors.defaults()
    for _, name in ipairs(NAMES) do
        if colors[name] ~= nil then
            local message = highlight_colors.check(colors[name])
            if message then
                return nil,
                    string.format("the color %s of search_highlight_colors %s", name, message)
            end
            completed[name] = colors[name]
        end
    end
    return completed, nil
end

highlight_colors.NAMES = NAMES

---Sets of the five colors that the window of the colors offers with one click.
highlight_colors.PRESETS = {
    { name = "Blue and amber", colors = highlight_colors.defaults() },
    {
        name = "Green and gold",
        colors = {
            selection = { hex = "#2E9E5B", alpha = 0.95 },
            hover = { white = 1, alpha = 0.16 },
            strong_match = { hex = "#F2C14E", alpha = 0.6 },
            medium_match = { hex = "#F2C14E", alpha = 0.36 },
            weak_match = { hex = "#F2C14E", alpha = 0.18 },
        },
    },
    {
        name = "Violet and teal",
        colors = {
            selection = { hex = "#8E5CF7", alpha = 0.95 },
            hover = { white = 1, alpha = 0.16 },
            strong_match = { hex = "#2EC4B6", alpha = 0.6 },
            medium_match = { hex = "#2EC4B6", alpha = 0.36 },
            weak_match = { hex = "#2EC4B6", alpha = 0.18 },
        },
    },
    {
        name = "High contrast",
        colors = {
            selection = { hex = "#FFFFFF", alpha = 0.9 },
            hover = { white = 1, alpha = 0.3 },
            strong_match = { hex = "#FF3B30", alpha = 0.8 },
            medium_match = { hex = "#FF9500", alpha = 0.7 },
            weak_match = { hex = "#FFCC00", alpha = 0.5 },
        },
    },
}

---@param value number from 0 to 1
---@return string two hexadecimal digits
local function to_byte(value)
    return string.format("%02X", math.floor(value * 255 + 0.5))
end

---@param color table a color that `highlight_colors.check` accepts
---@return string hex such as "#3373F2"
---@return number alpha from 0 to 1
function highlight_colors.to_hex_and_alpha(color)
    local alpha = color.alpha or 1
    if color.hex then
        return color.hex:upper(), alpha
    end
    if color.white then
        local gray = to_byte(color.white)
        return "#" .. gray .. gray .. gray, alpha
    end
    return "#" .. to_byte(color.red or 0) .. to_byte(color.green or 0) .. to_byte(color.blue or 0),
        alpha
end

---@param base HighlightColors the colors of the setting, completed with the defaults
---@param chosen table<string, table> the colors that the window of the colors chose, by name
---@return HighlightColors
function highlight_colors.apply(base, chosen)
    local colors = {}
    for _, name in ipairs(NAMES) do
        colors[name] = chosen[name] or base[name]
    end
    return colors
end

---@param raw any the colors of the saved state
---@return table<string, table> the valid colors by name, without the others
function highlight_colors.decode(raw)
    local chosen = {}
    if type(raw) ~= "table" then
        return chosen
    end
    for _, name in ipairs(NAMES) do
        if raw[name] ~= nil and highlight_colors.check(raw[name]) == nil then
            chosen[name] = raw[name]
        end
    end
    return chosen
end

return highlight_colors
