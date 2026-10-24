---The elements that the list, the search and the busy message draw alike on their canvases, and the
---frame that centers a canvas on the screen in front.
---Each canvas passes its own colors and opacities.
local canvas_elements = {}

---The radius of the corners of the background of the list and of the search.
canvas_elements.BACKGROUND_RADIUS = 14

---The radius of the corners of the backdrop behind a selected, hovered or matching item.
canvas_elements.BACKDROP_RADIUS = 6

---The images that the list and the search show: the icon of each application, and the preview of
---each window that has one.
---@class IconsAndPreviews
---@field app_icons table<string, table> the hs.image of each bundle id
---@field previews table<integer, table> the hs.image of each window id

---@param size table the w and h of the canvas
---@return table the frame that centers the canvas on the screen in front
function canvas_elements.center_on_screen(size)
    local screen = hs.screen.mainScreen():frame()
    return {
        x = screen.x + (screen.w - size.w) / 2,
        y = screen.y + (screen.h - size.h) / 2,
        w = size.w,
        h = size.h,
    }
end

---@param image table|nil an hs.image
---@param box table the x, y, w and h of the space for the image
---@param size table the w and h of the image
---@param alpha number|nil the opacity of the image, nil for the default of hs.canvas
---@return table|nil an image element centered in the box, nil without an image
function canvas_elements.build_centered_image(image, box, size, alpha)
    if not image then
        return nil
    end
    return {
        type = "image",
        image = image,
        imageScaling = "scaleToFit",
        imageAlpha = alpha,
        frame = {
            x = box.x + (box.w - size.w) / 2,
            y = box.y + (box.h - size.h) / 2,
            w = size.w,
            h = size.h,
        },
    }
end

---@param frame table|nil the x, y, w and h of the rectangle, nil for the whole canvas
---@param color table
---@param radius number the radius of the corners
---@param id string|nil
---@return table a filled rectangle element with rounded corners
function canvas_elements.build_rounded_rectangle(frame, color, radius, id)
    return {
        type = "rectangle",
        action = "fill",
        fillColor = color,
        roundedRectRadii = { xRadius = radius, yRadius = radius },
        frame = frame,
        id = id,
    }
end

return canvas_elements
