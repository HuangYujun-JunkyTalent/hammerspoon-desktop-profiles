---Draws the list of numbered applications and their windows in the middle of the screen in front.
local switch_overlay = {}

switch_overlay.MAX_TITLE_LENGTH = 60

local WIDTH = 560
local PADDING = 16
local LINE_HEIGHT = 24
local BACKGROUND_COLOR = { white = 0.12, alpha = 0.92 }
local SELECTION_COLOR = { red = 0.2, green = 0.45, blue = 0.95, alpha = 0.95 }
local TEXT_COLOR = { white = 1, alpha = 1 }
local DIMMED_TEXT_COLOR = { white = 0.75, alpha = 1 }

---@param line_count integer
---@return Rect
local function centered_frame(line_count)
    local screen = hs.screen.mainScreen():frame()
    local height = 2 * PADDING + line_count * LINE_HEIGHT
    return {
        x = screen.x + (screen.w - WIDTH) / 2,
        y = screen.y + (screen.h - height) / 2,
        w = WIDTH,
        h = height,
    }
end

---@param lines SwitchLine[]
---@return table[] the elements of an hs.canvas
local function build_elements(lines)
    local elements = {
        {
            type = "rectangle",
            action = "fill",
            fillColor = BACKGROUND_COLOR,
            roundedRectRadii = { xRadius = 14, yRadius = 14 },
        },
    }
    for index, line in ipairs(lines) do
        local top = PADDING + (index - 1) * LINE_HEIGHT
        if line.is_selected then
            table.insert(elements, {
                type = "rectangle",
                action = "fill",
                fillColor = SELECTION_COLOR,
                roundedRectRadii = { xRadius = 6, yRadius = 6 },
                frame = { x = PADDING / 2, y = top, w = WIDTH - PADDING, h = LINE_HEIGHT },
            })
        end
        table.insert(elements, {
            type = "text",
            text = line.text,
            textFont = line.is_application and "Helvetica-Bold" or "Helvetica",
            textSize = line.is_application and 16 or 14,
            textColor = (line.is_application or line.is_selected) and TEXT_COLOR
                or DIMMED_TEXT_COLOR,
            frame = { x = PADDING, y = top + 3, w = WIDTH - 2 * PADDING, h = LINE_HEIGHT },
        })
    end
    return elements
end

---@param lines SwitchLine[]
---@return table overlay an hs.canvas
function switch_overlay.show(lines)
    local overlay = hs.canvas.new(centered_frame(#lines))
    overlay:level(hs.canvas.windowLevels.overlay)
    overlay:replaceElements(build_elements(lines))
    overlay:show()
    return overlay
end

---@param overlay table an hs.canvas
---@param lines SwitchLine[]
function switch_overlay.update(overlay, lines)
    overlay:replaceElements(build_elements(lines))
end

---@param overlay table an hs.canvas
function switch_overlay.hide(overlay)
    overlay:delete()
end

return switch_overlay
