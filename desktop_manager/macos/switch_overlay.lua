---Draws the list of numbered applications and their windows in the middle of the screen in front.
local switch_overlay = {}

switch_overlay.MAX_TITLE_LENGTH = 60

---The images that the lines show: the icon of each application, and the preview of each window that
---has one.
---@class SwitchImages
---@field app_icons table<string, table> the hs.image of each bundle id
---@field previews table<integer, table> the hs.image of each window id

---The sizes of the list in points, which follow from the size of a preview and the size of the
---font.
---@class SwitchLayout
---@field preview_size table the w and h of a preview
---@field font_size number the size of the titles of windows
---@field application_font_size number
---@field icon_size number
---@field text_height number
---@field application_line_height number
---@field window_line_height number
---@field preview_inset number
---@field window_text_inset number
---@field application_text_inset number
---@field width number

local PADDING = 16
local GAP = 14
local LINE_HEIGHT_PER_POINT = 1.4
local CHARACTER_WIDTH_PER_POINT = 0.55
local BACKGROUND_COLOR = { white = 0.12, alpha = 0.92 }
local SELECTION_COLOR = { red = 0.2, green = 0.45, blue = 0.95, alpha = 0.95 }
local TEXT_COLOR = { white = 1, alpha = 1 }
local DIMMED_TEXT_COLOR = { white = 0.75, alpha = 1 }

---@param preview_size table the w and h of a preview in points
---@param font_size number the size of the titles in points, the names of applications 2 larger
---@return SwitchLayout
function switch_overlay.create_layout(preview_size, font_size)
    local application_font_size = font_size + 2
    local icon_size = math.floor(application_font_size * LINE_HEIGHT_PER_POINT + 0.5)
    local text_height = math.ceil(application_font_size * LINE_HEIGHT_PER_POINT)
    local preview_inset = PADDING + GAP
    local window_text_inset = preview_inset + preview_size.w + GAP
    local title_width =
        math.floor(switch_overlay.MAX_TITLE_LENGTH * font_size * CHARACTER_WIDTH_PER_POINT + 0.5)
    return {
        preview_size = { w = preview_size.w, h = preview_size.h },
        font_size = font_size,
        application_font_size = application_font_size,
        icon_size = icon_size,
        text_height = text_height,
        application_line_height = math.max(icon_size, text_height) + 8,
        window_line_height = math.max(preview_size.h, text_height) + 7,
        preview_inset = preview_inset,
        window_text_inset = window_text_inset,
        application_text_inset = PADDING + icon_size + 10,
        width = window_text_inset + title_width + PADDING,
    }
end

---@param line SwitchLine
---@param layout SwitchLayout
---@return number
local function height_of(line, layout)
    return line.is_application and layout.application_line_height or layout.window_line_height
end

---@param lines SwitchLine[]
---@param layout SwitchLayout
---@return Rect
local function centered_frame(lines, layout)
    local screen = hs.screen.mainScreen():frame()
    local height = 2 * PADDING
    for _, line in ipairs(lines) do
        height = height + height_of(line, layout)
    end
    return {
        x = screen.x + (screen.w - layout.width) / 2,
        y = screen.y + (screen.h - height) / 2,
        w = layout.width,
        h = height,
    }
end

---The icon of the application on its own line, and beside a window its preview, or the icon when
---the window has no preview.
---@param line SwitchLine
---@param top number
---@param images SwitchImages
---@param layout SwitchLayout
---@return table|nil the image element of the line
local function build_image_element(line, top, images, layout)
    local icon = images.app_icons[line.bundle_id]
    local preview = line.window_id and images.previews[line.window_id]
    local image = preview or icon
    if not image then
        return nil
    end
    local size = preview and layout.preview_size or { w = layout.icon_size, h = layout.icon_size }
    local left = line.is_application and PADDING
        or layout.preview_inset + (layout.preview_size.w - size.w) / 2
    return {
        type = "image",
        image = image,
        imageScaling = "scaleToFit",
        frame = {
            x = left,
            y = top + (height_of(line, layout) - size.h) / 2,
            w = size.w,
            h = size.h,
        },
    }
end

---@param line SwitchLine
---@param top number
---@param layout SwitchLayout
---@return table the text element of the line
local function build_text_element(line, top, layout)
    local inset = line.is_application and layout.application_text_inset or layout.window_text_inset
    local is_bright = line.is_application or line.is_selected
    return {
        type = "text",
        text = line.is_application and line.text or (line.text:gsub("^%s+", "")),
        textFont = line.is_application and "Helvetica-Bold" or "Helvetica",
        textSize = line.is_application and layout.application_font_size or layout.font_size,
        textColor = is_bright and TEXT_COLOR or DIMMED_TEXT_COLOR,
        frame = {
            x = inset,
            y = top + (height_of(line, layout) - layout.text_height) / 2,
            w = layout.width - inset - PADDING,
            h = layout.text_height,
        },
    }
end

---@param lines SwitchLine[]
---@param images SwitchImages
---@param layout SwitchLayout
---@return table[] the elements of an hs.canvas
local function build_elements(lines, images, layout)
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
        local height = height_of(line, layout)
        if line.is_selected then
            table.insert(elements, {
                type = "rectangle",
                action = "fill",
                fillColor = SELECTION_COLOR,
                roundedRectRadii = { xRadius = 6, yRadius = 6 },
                frame = { x = PADDING / 2, y = top, w = layout.width - PADDING, h = height },
            })
        end
        local image_element = build_image_element(line, top, images, layout)
        if image_element then
            table.insert(elements, image_element)
        end
        table.insert(elements, build_text_element(line, top, layout))
        top = top + height
    end
    return elements
end

---@param lines SwitchLine[]
---@param images SwitchImages
---@param layout SwitchLayout
---@return table overlay an hs.canvas
function switch_overlay.show(lines, images, layout)
    local overlay = hs.canvas.new(centered_frame(lines, layout))
    overlay:level(hs.canvas.windowLevels.overlay)
    overlay:replaceElements(build_elements(lines, images, layout))
    overlay:show()
    return overlay
end

---@param overlay table an hs.canvas
---@param lines SwitchLine[]
---@param images SwitchImages
---@param layout SwitchLayout
function switch_overlay.update(overlay, lines, images, layout)
    overlay:replaceElements(build_elements(lines, images, layout))
end

---@param overlay table an hs.canvas
function switch_overlay.hide(overlay)
    overlay:delete()
end

return switch_overlay
