---Draws the list of numbered applications and their windows in the middle of the screen in front.
local switch_overlay = {}

switch_overlay.MAX_TITLE_LENGTH = 60

---The images that the lines show: the icon of each application, and the preview of each window that
---has one.
---@class SwitchImages
---@field app_icons table<string, table> the hs.image of each bundle id
---@field previews table<integer, table> the hs.image of each window id

local WIDTH = 620
local PADDING = 16
local APPLICATION_LINE_HEIGHT = 30
local WINDOW_LINE_HEIGHT = 42
local ICON_SIZE = 22
local PREVIEW_SIZE = { w = 56, h = 35 }
local PREVIEW_INSET = PADDING + 14
local WINDOW_TEXT_INSET = PREVIEW_INSET + PREVIEW_SIZE.w + 14
local APPLICATION_TEXT_INSET = PADDING + ICON_SIZE + 10
local TEXT_HEIGHT = 22
local BACKGROUND_COLOR = { white = 0.12, alpha = 0.92 }
local SELECTION_COLOR = { red = 0.2, green = 0.45, blue = 0.95, alpha = 0.95 }
local TEXT_COLOR = { white = 1, alpha = 1 }
local DIMMED_TEXT_COLOR = { white = 0.75, alpha = 1 }

---@param line SwitchLine
---@return integer
local function height_of(line)
    return line.is_application and APPLICATION_LINE_HEIGHT or WINDOW_LINE_HEIGHT
end

---@param lines SwitchLine[]
---@return Rect
local function centered_frame(lines)
    local screen = hs.screen.mainScreen():frame()
    local height = 2 * PADDING
    for _, line in ipairs(lines) do
        height = height + height_of(line)
    end
    return {
        x = screen.x + (screen.w - WIDTH) / 2,
        y = screen.y + (screen.h - height) / 2,
        w = WIDTH,
        h = height,
    }
end

---The icon of the application on its own line, and beside a window its preview, or the icon when
---the window has no preview.
---@param line SwitchLine
---@param top number
---@param images SwitchImages
---@return table|nil the image element of the line
local function build_image_element(line, top, images)
    local icon = images.app_icons[line.bundle_id]
    local preview = line.window_id and images.previews[line.window_id]
    local image = preview or icon
    if not image then
        return nil
    end
    local size = preview and PREVIEW_SIZE or { w = ICON_SIZE, h = ICON_SIZE }
    local left = line.is_application and PADDING or PREVIEW_INSET + (PREVIEW_SIZE.w - size.w) / 2
    return {
        type = "image",
        image = image,
        imageScaling = "scaleToFit",
        frame = { x = left, y = top + (height_of(line) - size.h) / 2, w = size.w, h = size.h },
    }
end

---@param line SwitchLine
---@param top number
---@return table the text element of the line
local function build_text_element(line, top)
    local inset = line.is_application and APPLICATION_TEXT_INSET or WINDOW_TEXT_INSET
    local is_bright = line.is_application or line.is_selected
    return {
        type = "text",
        text = line.is_application and line.text or (line.text:gsub("^%s+", "")),
        textFont = line.is_application and "Helvetica-Bold" or "Helvetica",
        textSize = line.is_application and 16 or 14,
        textColor = is_bright and TEXT_COLOR or DIMMED_TEXT_COLOR,
        frame = {
            x = inset,
            y = top + (height_of(line) - TEXT_HEIGHT) / 2,
            w = WIDTH - inset - PADDING,
            h = TEXT_HEIGHT,
        },
    }
end

---@param lines SwitchLine[]
---@param images SwitchImages
---@return table[] the elements of an hs.canvas
local function build_elements(lines, images)
    local elements = {
        {
            type = "rectangle",
            action = "fill",
            fillColor = BACKGROUND_COLOR,
            roundedRectRadii = { xRadius = 14, yRadius = 14 },
        },
    }
    local top = PADDING
    for _, line in ipairs(lines) do
        if line.is_selected then
            table.insert(elements, {
                type = "rectangle",
                action = "fill",
                fillColor = SELECTION_COLOR,
                roundedRectRadii = { xRadius = 6, yRadius = 6 },
                frame = { x = PADDING / 2, y = top, w = WIDTH - PADDING, h = height_of(line) },
            })
        end
        local image_element = build_image_element(line, top, images)
        if image_element then
            table.insert(elements, image_element)
        end
        table.insert(elements, build_text_element(line, top))
        top = top + height_of(line)
    end
    return elements
end

---@param lines SwitchLine[]
---@param images SwitchImages
---@return table overlay an hs.canvas
function switch_overlay.show(lines, images)
    local overlay = hs.canvas.new(centered_frame(lines))
    overlay:level(hs.canvas.windowLevels.overlay)
    overlay:replaceElements(build_elements(lines, images))
    overlay:show()
    return overlay
end

---@param overlay table an hs.canvas
---@param lines SwitchLine[]
---@param images SwitchImages
function switch_overlay.update(overlay, lines, images)
    overlay:replaceElements(build_elements(lines, images))
end

---@param overlay table an hs.canvas
function switch_overlay.hide(overlay)
    overlay:delete()
end

return switch_overlay
