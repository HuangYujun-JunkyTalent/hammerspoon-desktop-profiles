local canvas_elements = require("desktop_manager.macos.canvas_elements")

---Draws the panel of the search of the windows in the middle of the screen in front: the search
---line on top, the previews of the windows in view in a grid, and the applications in a row at the
---bottom.
---Each preview and each application carries a transparent element on top that tracks the mouse,
---with the id "window:<window id>" or "application:<bundle id>".
local search_overlay = {}

---@class SearchOverlaySettings
---@field font_size number the size of the titles, as a fraction of the height of the screen
---@field preview_size table the w and h of a preview, as fractions of the width and height of the
---screen, which give the shape of the previews
---@field highlight_colors HighlightColors

---@class SearchOverlay
---@field canvas table an hs.canvas
---@field settings SearchOverlaySettings
---@field column_count integer the columns of the grid of the previews in the last drawing

---The sizes and the places of the parts of the panel, in points from its top left corner.
---@class SearchLayout
---@field size table the w and h of the panel
---@field font_size number
---@field line_height number the height of a line of a title
---@field search_frame table
---@field preview_area table the x, y, w and h of the space of the previews
---@field cell_size table the w and h of a preview with its two lines of text
---@field preview_size table the w and h of a preview
---@field column_count integer
---@field icon_size number
---@field bar_top number
---@field button_size table the w and h of an application in the row
---@field buttons_per_row integer
---@field colors HighlightColors the colors behind the selected, hovered and matching items, by the
---match levels of fuzzy_match with "_match" after them

local PANEL_WIDTH_SHARE = 0.8
local PREVIEW_AREA_HEIGHT_SHARE = 0.5
local MAX_PREVIEW_WIDTH_SHARE = 0.3
local FONT_SCALE = 1.4
local MIN_FONT_SIZE = 11
local ICON_HEIGHT_SHARE = 0.045
local MIN_ICON_SIZE = 32
local MIN_BUTTON_WIDTH = 72
local MAX_BUTTON_WIDTH = 120
local PADDING = 16
local GAP = 12
local CELL_PADDING = 8
local LINE_HEIGHT_PER_POINT = 1.4
local CARET = "▏"
local NO_WINDOW_NOTE = "No window matches"
local BACKGROUND_COLOR = { white = 0.12, alpha = 0.94 }
local SEARCH_FIELD_COLOR = { white = 1, alpha = 0.1 }
local TRACKING_COLOR = { white = 0, alpha = 0 }
local TEXT_COLOR = { white = 1, alpha = 1 }
local DIMMED_TEXT_COLOR = { white = 0.7, alpha = 1 }
local FADED_TEXT_COLOR = { white = 0.42, alpha = 1 }
local FADED_IMAGE_ALPHA = 0.3

---@param settings SearchOverlaySettings
---@param screen table the frame of the screen in front
---@return number the width of a preview divided by its height
local function measure_aspect(settings, screen)
    return settings.preview_size.w * screen.w / (settings.preview_size.h * screen.h)
end

---The grid of the previews: the number of columns that gives the widest previews within the area,
---with previews of the shape of the setting, at most MAX_PREVIEW_WIDTH_SHARE of the screen wide.
---@param count integer the windows in view
---@param area table the w and h of the space of the previews
---@param text_height number the height of the two lines under a preview
---@param aspect number
---@param max_width number
---@return integer column_count
---@return table preview_size
local function fit_grid(count, area, text_height, aspect, max_width)
    local best_columns, best_size = 1, { w = 0, h = 0 }
    for columns = 1, math.max(1, count) do
        local rows = math.ceil(math.max(1, count) / columns)
        local width = (area.w - (columns - 1) * GAP) / columns - 2 * CELL_PADDING
        local height_limit = (area.h - (rows - 1) * GAP) / rows - text_height - 2 * CELL_PADDING
        width = math.min(width, height_limit * aspect, max_width)
        if width > best_size.w then
            best_columns, best_size =
                columns, { w = math.floor(width), h = math.floor(width / aspect) }
        end
    end
    return best_columns, best_size
end

---@param view SearchView
---@param settings SearchOverlaySettings
---@param screen table the frame of the screen in front
---@return SearchLayout
local function lay_out(view, settings, screen)
    local font_size = math.max(MIN_FONT_SIZE, settings.font_size * screen.h * FONT_SCALE)
    local line_height = math.ceil(font_size * LINE_HEIGHT_PER_POINT)
    local width = math.floor(screen.w * PANEL_WIDTH_SHARE)
    local inner_width = width - 2 * PADDING
    local search_height = math.ceil((font_size + 3) * LINE_HEIGHT_PER_POINT) + CELL_PADDING
    local preview_area = {
        x = PADDING,
        y = PADDING + search_height + GAP,
        w = inner_width,
        h = math.floor(screen.h * PREVIEW_AREA_HEIGHT_SHARE),
    }
    local column_count, preview_size = fit_grid(
        #view.windows,
        preview_area,
        2 * line_height,
        measure_aspect(settings, screen),
        screen.w * MAX_PREVIEW_WIDTH_SHARE
    )
    local icon_size = math.max(MIN_ICON_SIZE, math.floor(screen.h * ICON_HEIGHT_SHARE))
    local button_count = math.max(1, #view.applications)
    local button_width =
        math.max(MIN_BUTTON_WIDTH, math.min(MAX_BUTTON_WIDTH, inner_width / button_count))
    local buttons_per_row = math.max(1, math.floor(inner_width / button_width))
    local button_height = icon_size + line_height + 2 * CELL_PADDING + 4
    local bar_top = preview_area.y + preview_area.h + GAP
    local row_count = math.ceil(button_count / buttons_per_row)
    return {
        size = { w = width, h = bar_top + row_count * button_height + PADDING },
        font_size = font_size,
        line_height = line_height,
        search_frame = { x = PADDING, y = PADDING, w = inner_width, h = search_height },
        preview_area = preview_area,
        preview_size = preview_size,
        cell_size = {
            w = preview_size.w + 2 * CELL_PADDING,
            h = preview_size.h + 2 * line_height + 2 * CELL_PADDING,
        },
        column_count = column_count,
        icon_size = icon_size,
        bar_top = bar_top,
        button_size = { w = button_width, h = button_height },
        buttons_per_row = buttons_per_row,
        colors = settings.highlight_colors,
    }
end

---@param text string
---@param frame table
---@param font_size number
---@param color table
---@param id string|nil "faded" for a faded text
---@return table a text element of one line, cut at its end when it is too long
local function build_text(text, frame, font_size, color, id)
    return {
        type = "text",
        text = text,
        textFont = "Helvetica",
        textSize = font_size,
        textColor = color,
        textLineBreak = "truncateTail",
        frame = frame,
        id = id,
    }
end

---@param is_faded boolean
---@param color table the color of the text when it does not fade
---@return table color the color of the text
---@return string|nil id the id of a faded text
local function choose_text_color(is_faded, color)
    if is_faded then
        return FADED_TEXT_COLOR, "faded"
    end
    return color, nil
end

---@param colors HighlightColors
---@param match_level string a match level of fuzzy_match
---@return table color the color behind an item of the match level
---@return string id the id of the backdrop
local function choose_match_backdrop(colors, match_level)
    return colors[match_level .. "_match"], "match-" .. match_level
end

---@param frame table
---@param color table
---@param id string
---@return table a rectangle element behind an item
local function build_backdrop(frame, color, id)
    return canvas_elements.build_rounded_rectangle(
        frame,
        color,
        canvas_elements.BACKDROP_RADIUS,
        id
    )
end

---@param frame table
---@param id string
---@return table a transparent element on top of an item, which reports the mouse over its frame
local function build_tracker(frame, id)
    return {
        type = "rectangle",
        action = "fill",
        fillColor = TRACKING_COLOR,
        frame = frame,
        id = id,
        trackMouseByBounds = true,
        trackMouseEnterExit = true,
        trackMouseUp = true,
    }
end

---@param image table|nil an hs.image
---@param box table the space for the image
---@param size table the w and h of the image
---@param is_faded boolean
---@return table|nil an image element centered in the box
local function build_image(image, box, size, is_faded)
    return canvas_elements.build_centered_image(
        image,
        box,
        size,
        is_faded and FADED_IMAGE_ALPHA or 1
    )
end

---@param elements table[]
---@param line SearchLine
---@param layout SearchLayout
local function draw_search_line(elements, line, layout)
    local field = layout.search_frame
    table.insert(elements, build_backdrop(field, SEARCH_FIELD_COLOR, "search-field"))
    local summary_width = math.floor(field.w * 0.35)
    local is_typed = line.text ~= ""
    local typed_color, typed_id = choose_text_color(not is_typed, TEXT_COLOR)
    local typed = build_text(is_typed and line.text .. CARET or line.placeholder, {
        x = field.x + CELL_PADDING,
        y = field.y + CELL_PADDING / 2,
        w = field.w - summary_width - 3 * CELL_PADDING,
        h = field.h - CELL_PADDING,
    }, layout.font_size + 3, typed_color, typed_id)
    typed.textLineBreak = "truncateHead"
    table.insert(elements, typed)
    local summary = build_text(line.summary, {
        x = field.x + field.w - CELL_PADDING - summary_width,
        y = field.y + (field.h - layout.line_height) / 2,
        w = summary_width,
        h = layout.line_height,
    }, layout.font_size, DIMMED_TEXT_COLOR)
    summary.textAlignment = "right"
    table.insert(elements, summary)
end

---Draws one window in the grid of the previews: its backdrop when it is selected or matches, its
---preview or else the icon of its application, its title, the name of its application, and the
---element that tracks the mouse.
---@param elements table[]
---@param window SearchViewWindow
---@param frame table the x, y, w and h of the cell
---@param images SwitchImages
---@param layout SearchLayout
local function draw_preview_cell(elements, window, frame, images, layout)
    if window.is_selected then
        table.insert(elements, build_backdrop(frame, layout.colors.selection, "selection"))
    elseif window.match_level then
        local color, backdrop_id = choose_match_backdrop(layout.colors, window.match_level)
        table.insert(elements, build_backdrop(frame, color, backdrop_id))
    end
    local box = {
        x = frame.x + CELL_PADDING,
        y = frame.y + CELL_PADDING,
        w = layout.preview_size.w,
        h = layout.preview_size.h,
    }
    local preview = images.previews[window.window_id]
    local image = build_image(
        preview or images.app_icons[window.bundle_id],
        box,
        preview and layout.preview_size or { w = layout.icon_size, h = layout.icon_size },
        false
    )
    if image then
        table.insert(elements, image)
    end
    local text_top = box.y + box.h
    table.insert(
        elements,
        build_text(
            window.title,
            { x = box.x, y = text_top, w = box.w, h = layout.line_height },
            layout.font_size,
            TEXT_COLOR
        )
    )
    table.insert(
        elements,
        build_text(window.app_name, {
            x = box.x,
            y = text_top + layout.line_height,
            w = box.w,
            h = layout.line_height,
        }, layout.font_size, DIMMED_TEXT_COLOR)
    )
    table.insert(elements, build_tracker(frame, "window:" .. window.window_id))
end

---@param elements table[]
---@param windows SearchViewWindow[]
---@param images SwitchImages
---@param layout SearchLayout
local function draw_previews(elements, windows, images, layout)
    local area = layout.preview_area
    if #windows == 0 then
        table.insert(
            elements,
            build_text(NO_WINDOW_NOTE, {
                x = area.x,
                y = area.y + (area.h - layout.line_height) / 2,
                w = area.w,
                h = layout.line_height,
            }, layout.font_size, DIMMED_TEXT_COLOR)
        )
        elements[#elements].textAlignment = "center"
        elements[#elements].id = "no-window-note"
        return
    end
    local columns = layout.column_count
    local rows = math.ceil(#windows / columns)
    local cell = layout.cell_size
    local grid_width = math.min(#windows, columns) * cell.w
        + (math.min(#windows, columns) - 1) * GAP
    local grid_height = rows * cell.h + (rows - 1) * GAP
    local left = area.x + (area.w - grid_width) / 2
    local top = area.y + (area.h - grid_height) / 2
    for index, window in ipairs(windows) do
        draw_preview_cell(elements, window, {
            x = left + ((index - 1) % columns) * (cell.w + GAP),
            y = top + math.floor((index - 1) / columns) * (cell.h + GAP),
            w = cell.w,
            h = cell.h,
        }, images, layout)
    end
end

---@param application SearchViewApplication
---@param colors HighlightColors
---@return table|nil the color behind the application, and the id of its backdrop
---@return string|nil
local function choose_application_backdrop(application, colors)
    if application.is_chosen then
        return colors.selection, "selection"
    end
    if application.is_hovered then
        return colors.hover, "hovered"
    end
    if application.match_level then
        return choose_match_backdrop(colors, application.match_level)
    end
    return nil, nil
end

---@param elements table[]
---@param applications SearchViewApplication[]
---@param images SwitchImages
---@param layout SearchLayout
local function draw_applications(elements, applications, images, layout)
    local button = layout.button_size
    local per_row = layout.buttons_per_row
    for index, application in ipairs(applications) do
        local row = math.floor((index - 1) / per_row)
        local row_count = math.min(per_row, #applications - row * per_row)
        local row_left = PADDING + (layout.size.w - 2 * PADDING - row_count * button.w) / 2
        local frame = {
            x = row_left + ((index - 1) % per_row) * button.w,
            y = layout.bar_top + row * button.h,
            w = button.w,
            h = button.h,
        }
        local color, backdrop_id = choose_application_backdrop(application, layout.colors)
        if color then
            table.insert(elements, build_backdrop(frame, color, backdrop_id))
        end
        local image = build_image(images.app_icons[application.bundle_id], {
            x = frame.x,
            y = frame.y + CELL_PADDING,
            w = frame.w,
            h = layout.icon_size,
        }, { w = layout.icon_size, h = layout.icon_size }, application.is_faded)
        if image then
            table.insert(elements, image)
        end
        if application.number then
            local number_color, number_id =
                choose_text_color(application.is_faded, DIMMED_TEXT_COLOR)
            table.insert(
                elements,
                build_text(tostring(application.number), {
                    x = frame.x + CELL_PADDING / 2,
                    y = frame.y + CELL_PADDING / 2,
                    w = layout.line_height,
                    h = layout.line_height,
                }, layout.font_size, number_color, number_id)
            )
        end
        local name_color, name_id = choose_text_color(application.is_faded, TEXT_COLOR)
        local name = build_text(application.app_name, {
            x = frame.x + CELL_PADDING / 2,
            y = frame.y + CELL_PADDING + layout.icon_size + 4,
            w = frame.w - CELL_PADDING,
            h = layout.line_height,
        }, layout.font_size, name_color, name_id)
        name.textAlignment = "center"
        table.insert(elements, name)
        table.insert(elements, build_tracker(frame, "application:" .. application.bundle_id))
    end
end

---@param view SearchView
---@param images SwitchImages
---@param layout SearchLayout
---@return table[] elements
local function draw_panel(view, images, layout)
    local elements = {
        canvas_elements.build_rounded_rectangle(
            nil,
            BACKGROUND_COLOR,
            canvas_elements.BACKGROUND_RADIUS,
            nil
        ),
    }
    draw_search_line(elements, view.line, layout)
    draw_previews(elements, view.windows, images, layout)
    draw_applications(elements, view.applications, images, layout)
    return elements
end

---@param view SearchView
---@param images SwitchImages
---@param settings SearchOverlaySettings
---@param on_mouse fun(message: string, id: string) receives "mouseEnter", "mouseExit" and
---"mouseUp" with the id of the element, and "mouseExit" with "_canvas_" when the mouse leaves the
---panel
---@return SearchOverlay
function search_overlay.show(view, images, settings, on_mouse)
    local layout = lay_out(view, settings, hs.screen.mainScreen():frame())
    local canvas = hs.canvas.new(canvas_elements.center_on_screen(layout.size))
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:mouseCallback(function(_, message, id)
        on_mouse(message, tostring(id))
    end)
    canvas:canvasMouseEvents(nil, nil, true, nil)
    canvas:replaceElements(draw_panel(view, images, layout))
    canvas:show()
    return { canvas = canvas, settings = settings, column_count = layout.column_count }
end

---@param overlay SearchOverlay
---@param view SearchView
---@param images SwitchImages
function search_overlay.update(overlay, view, images)
    local layout = lay_out(view, overlay.settings, hs.screen.mainScreen():frame())
    overlay.canvas:frame(canvas_elements.center_on_screen(layout.size))
    overlay.canvas:replaceElements(draw_panel(view, images, layout))
    overlay.column_count = layout.column_count
end

---@param overlay SearchOverlay
---@return table the w and h in points that the snapshots render for: a preview in a grid of three
---columns and two rows
function search_overlay.read_preview_size(overlay)
    local screen = hs.screen.mainScreen():frame()
    local layout = lay_out({ windows = {}, applications = {} }, overlay.settings, screen)
    local _, preview_size = fit_grid(
        6,
        layout.preview_area,
        2 * layout.line_height,
        measure_aspect(overlay.settings, screen),
        screen.w * MAX_PREVIEW_WIDTH_SHARE
    )
    return preview_size
end

---@param overlay SearchOverlay
function search_overlay.hide(overlay)
    overlay.canvas:delete()
end

return search_overlay
