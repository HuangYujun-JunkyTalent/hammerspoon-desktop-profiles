local list_sizing = require("desktop_manager.core.list_sizing")
local switch_list = require("desktop_manager.core.switch_list")

---Draws the list of numbered applications and their windows in the middle of the screen in front,
---as rows of lines or as columns of applications.
local switch_overlay = {}

switch_overlay.MAX_TITLE_LENGTH = 60

---The images that the list shows: the icon of each application, and the preview of each window that
---has one.
---@class SwitchImages
---@field app_icons table<string, table> the hs.image of each bundle id
---@field previews table<integer, table> the hs.image of each window id

---What the list shows: lines for the rows, or groups of columns.
---@class SwitchView
---@field lines SwitchLine[]|nil
---@field groups SwitchColumnGroup[]|nil

---The sizes of the list as fractions of the screen in front.
---@class SwitchRelativeSizes
---@field preview_size table the w and h of a preview, as fractions of the width and height
---@field font_size number the size of the titles, as a fraction of the height
---@field sizing string a value of list_sizing

---The sizes of the list in points, which the fit to the screen chose.
---@class SwitchSizes
---@field preview_size table the w and h of a preview in points
---@field font_size number the size of the titles in points
---@field application_font_size number
---@field icon_size number
---@field text_height number

---A list on the screen: its canvas, its sizes in points and the number of lines of its columns.
---@class SwitchOverlay
---@field canvas table an hs.canvas
---@field sizes SwitchSizes
---@field line_count integer

local PADDING = 16
local GAP = 14
local COLUMN_GAP = 10
local GROUP_GAP = 28
local LINE_GAP = 18
local CELL_PADDING = 8
local LINE_HEIGHT_PER_POINT = 1.4
local CHARACTER_WIDTH_PER_POINT = 0.55
local HEADER_CHARACTERS = 12
local MAX_WIDTH_SHARE = 0.95
local MAX_HEIGHT_SHARE = 0.9
local FIT_ROUNDS = 10
local MAX_FILL_SCALE = 2.5
local MAX_FONT_SCALE = 1.6
local MAX_LINE_COUNT = 2
local REQUIRED_GAIN_OF_ANOTHER_LINE = 1.05
local NO_WINDOW_NOTE = "no window, a new one opens"
local BACKGROUND_COLOR = { white = 0.12, alpha = 0.92 }
local SELECTION_COLOR = { red = 0.2, green = 0.45, blue = 0.95, alpha = 0.95 }
local TEXT_COLOR = { white = 1, alpha = 1 }
local DIMMED_TEXT_COLOR = { white = 0.75, alpha = 1 }

---@param preview_size table the w and h of a preview in points
---@param font_size number the size of the titles in points
---@return SwitchSizes
local function create_sizes(preview_size, font_size)
    local application_font_size = font_size + 2
    return {
        preview_size = { w = preview_size.w, h = preview_size.h },
        font_size = font_size,
        application_font_size = application_font_size,
        icon_size = math.floor(application_font_size * LINE_HEIGHT_PER_POINT + 0.5),
        text_height = math.ceil(application_font_size * LINE_HEIGHT_PER_POINT),
    }
end

---@param width number in points
---@param font_size number in points
---@return integer the characters of a title that fit the width
local function count_fitting_characters(width, font_size)
    return math.max(4, math.floor(width / (font_size * CHARACTER_WIDTH_PER_POINT)))
end

---An image element centered in its box, at the size of a preview or of an icon.
---@param sizes SwitchSizes
---@param image table|nil an hs.image
---@param is_preview boolean
---@param box table the x, y, w and h of the space for the image
---@return table|nil
local function build_image(sizes, image, is_preview, box)
    if not image then
        return nil
    end
    local size = is_preview and sizes.preview_size or { w = sizes.icon_size, h = sizes.icon_size }
    return {
        type = "image",
        image = image,
        imageScaling = "scaleToFit",
        frame = {
            x = box.x + (box.w - size.w) / 2,
            y = box.y + (box.h - size.h) / 2,
            w = size.w,
            h = size.h,
        },
    }
end

---@class TextStyle
---@field font_size number
---@field is_bold boolean
---@field is_bright boolean

---@param text string
---@param frame table
---@param style TextStyle
---@return table a text element
local function build_text(text, frame, style)
    return {
        type = "text",
        text = text,
        textFont = style.is_bold and "Helvetica-Bold" or "Helvetica",
        textSize = style.font_size,
        textColor = style.is_bright and TEXT_COLOR or DIMMED_TEXT_COLOR,
        frame = frame,
    }
end

---@param frame table
---@return table a rectangle element behind a selected line or cell
local function build_selection(frame)
    return {
        type = "rectangle",
        action = "fill",
        fillColor = SELECTION_COLOR,
        roundedRectRadii = { xRadius = 6, yRadius = 6 },
        frame = frame,
    }
end

---@return table the rectangle element of the background
local function build_background()
    return {
        type = "rectangle",
        action = "fill",
        fillColor = BACKGROUND_COLOR,
        roundedRectRadii = { xRadius = 14, yRadius = 14 },
    }
end

---Draws the rows: each application on a line, and under it a line per window with its preview.
---@param lines SwitchLine[]
---@param images SwitchImages
---@param sizes SwitchSizes
---@return table[] elements
---@return table size the w and h of the list
local function draw_rows(lines, images, sizes)
    local application_line_height = math.max(sizes.icon_size, sizes.text_height) + 8
    local window_line_height = math.max(sizes.preview_size.h, sizes.text_height) + 7
    local preview_inset = PADDING + GAP
    local window_text_inset = preview_inset + sizes.preview_size.w + GAP
    local application_text_inset = PADDING + sizes.icon_size + 10
    local title_width = math.floor(
        switch_overlay.MAX_TITLE_LENGTH * sizes.font_size * CHARACTER_WIDTH_PER_POINT + 0.5
    )
    local width = window_text_inset + title_width + PADDING
    local elements = { build_background() }
    local top = PADDING
    for _, line in ipairs(lines) do
        local height = line.is_application and application_line_height or window_line_height
        if line.is_selected then
            table.insert(
                elements,
                build_selection({ x = PADDING / 2, y = top, w = width - PADDING, h = height })
            )
        end
        local preview = line.window_id and images.previews[line.window_id]
        local box = { x = preview_inset, y = top, w = sizes.preview_size.w, h = height }
        if line.is_application then
            box = { x = PADDING, y = top, w = sizes.icon_size, h = height }
        end
        local image =
            build_image(sizes, preview or images.app_icons[line.bundle_id], preview ~= nil, box)
        if image then
            table.insert(elements, image)
        end
        local inset = line.is_application and application_text_inset or window_text_inset
        local text = line.is_application and line.text or (line.text:gsub("^%s+", ""))
        table.insert(
            elements,
            build_text(text, {
                x = inset,
                y = top + (height - sizes.text_height) / 2,
                w = width - inset - PADDING,
                h = sizes.text_height,
            }, {
                font_size = line.is_application and sizes.application_font_size or sizes.font_size,
                is_bold = line.is_application,
                is_bright = line.is_application or line.is_selected,
            })
        )
        top = top + height
    end
    return elements, { w = width, h = top + PADDING }
end

---The sizes in points that the columns derive from the sizes of the list.
---@class ColumnMetrics
---@field title_height number
---@field header_height number
---@field cell_height number
---@field column_width number
---@field title_width number

---@param sizes SwitchSizes
---@return ColumnMetrics
local function measure_columns(sizes)
    local title_height = math.ceil(sizes.font_size * LINE_HEIGHT_PER_POINT)
    local column_width = math.max(
        sizes.preview_size.w,
        HEADER_CHARACTERS * sizes.application_font_size
    ) + 2 * CELL_PADDING
    return {
        title_height = title_height,
        header_height = math.max(sizes.icon_size, sizes.text_height) + 8,
        cell_height = sizes.preview_size.h + title_height + 3 * CELL_PADDING / 2,
        column_width = column_width,
        title_width = column_width - 2 * CELL_PADDING,
    }
end

---Draws the header of a column: the icon, the number and the name of the application.
---@param elements table[]
---@param column SwitchColumn
---@param origin table the x and y of the column
---@param images SwitchImages
---@param sizes SwitchSizes
---@param metrics ColumnMetrics
local function draw_column_header(elements, column, origin, images, sizes, metrics)
    if column.is_selected then
        table.insert(
            elements,
            build_selection({
                x = origin.x,
                y = origin.y,
                w = metrics.column_width,
                h = metrics.header_height,
            })
        )
    end
    local icon = build_image(sizes, images.app_icons[column.bundle_id], false, {
        x = origin.x + CELL_PADDING,
        y = origin.y,
        w = sizes.icon_size,
        h = metrics.header_height,
    })
    if icon then
        table.insert(elements, icon)
    end
    local inset = CELL_PADDING + sizes.icon_size + 6
    local width = metrics.column_width - inset - CELL_PADDING
    local text = switch_list.shorten(
        string.format("%d  %s", column.number, column.app_name),
        count_fitting_characters(width, sizes.application_font_size)
    )
    table.insert(
        elements,
        build_text(text, {
            x = origin.x + inset,
            y = origin.y + (metrics.header_height - sizes.text_height) / 2,
            w = width,
            h = sizes.text_height,
        }, { font_size = sizes.application_font_size, is_bold = true, is_bright = true })
    )
end

---Draws the windows of a column downward, each a preview with its title under it.
---@param elements table[]
---@param column SwitchColumn
---@param origin table the x and y of the first cell
---@param images SwitchImages
---@param sizes SwitchSizes
---@param metrics ColumnMetrics
local function draw_column_cells(elements, column, origin, images, sizes, metrics)
    local characters = count_fitting_characters(metrics.title_width, sizes.font_size)
    local dimmed_style = { font_size = sizes.font_size, is_bold = false, is_bright = false }
    if #column.cells == 0 then
        table.insert(
            elements,
            build_text(switch_list.shorten(NO_WINDOW_NOTE, characters), {
                x = origin.x + CELL_PADDING,
                y = origin.y + CELL_PADDING,
                w = metrics.title_width,
                h = metrics.title_height,
            }, dimmed_style)
        )
    end
    local top = origin.y
    for _, cell in ipairs(column.cells) do
        if cell.is_selected then
            table.insert(
                elements,
                build_selection({
                    x = origin.x,
                    y = top,
                    w = metrics.column_width,
                    h = metrics.cell_height,
                })
            )
        end
        local preview = images.previews[cell.window_id]
        local image =
            build_image(sizes, preview or images.app_icons[column.bundle_id], preview ~= nil, {
                x = origin.x + CELL_PADDING,
                y = top + CELL_PADDING / 2,
                w = metrics.title_width,
                h = sizes.preview_size.h,
            })
        if image then
            table.insert(elements, image)
        end
        table.insert(
            elements,
            build_text(switch_list.shorten(cell.title, characters), {
                x = origin.x + CELL_PADDING,
                y = top + CELL_PADDING + sizes.preview_size.h,
                w = metrics.title_width,
                h = metrics.title_height,
            }, {
                font_size = sizes.font_size,
                is_bold = false,
                is_bright = cell.is_selected,
            })
        )
        top = top + metrics.cell_height
    end
end

---A run of columns of one group on one line of the list.
---@class ColumnSegment
---@field display_name string|nil
---@field columns SwitchColumn[]

---Folds the columns into lines, the first lines taking the larger share, so the numbers read from
---left to right and then downward.
---A group of a display that continues on the next line starts a new segment there.
---@param groups SwitchColumnGroup[]
---@param line_count integer
---@return ColumnSegment[][] the segments of each line
local function fold_columns(groups, line_count)
    local entries = {}
    for _, group in ipairs(groups) do
        for _, column in ipairs(group.columns) do
            table.insert(entries, { group = group, column = column })
        end
    end
    local per_line = math.max(1, math.ceil(#entries / line_count))
    local lines = {}
    for index, entry in ipairs(entries) do
        local line_index = math.floor((index - 1) / per_line) + 1
        lines[line_index] = lines[line_index] or {}
        local segments = lines[line_index]
        local last = segments[#segments]
        if last and last.group == entry.group then
            table.insert(last.columns, entry.column)
        else
            table.insert(segments, {
                group = entry.group,
                display_name = entry.group.display_name,
                columns = { entry.column },
            })
        end
    end
    return lines
end

---Draws the columns: a column per application with its windows stacked downward, the name of a
---display above its columns, and the columns folded into the given number of lines.
---@param groups SwitchColumnGroup[]
---@param images SwitchImages
---@param sizes SwitchSizes
---@param line_count integer
---@return table[] elements
---@return table size the w and h of the list
local function draw_columns(groups, images, sizes, line_count)
    local metrics = measure_columns(sizes)
    local has_display_names = false
    for _, group in ipairs(groups) do
        has_display_names = has_display_names or group.display_name ~= nil
    end
    local label_height = has_display_names and metrics.title_height + 6 or 0
    local elements = { build_background() }
    local top, width = PADDING, 0
    local lines = fold_columns(groups, line_count)
    for line_index, segments in ipairs(lines) do
        local most_cells = 1
        for _, segment in ipairs(segments) do
            for _, column in ipairs(segment.columns) do
                most_cells = math.max(most_cells, #column.cells)
            end
        end
        local columns_top = top + label_height
        local left = PADDING
        for segment_index, segment in ipairs(segments) do
            if segment.display_name then
                local segment_width = #segment.columns * (metrics.column_width + COLUMN_GAP)
                    - COLUMN_GAP
                table.insert(
                    elements,
                    build_text(
                        segment.display_name,
                        { x = left, y = top, w = segment_width, h = metrics.title_height },
                        { font_size = sizes.font_size, is_bold = false, is_bright = false }
                    )
                )
            end
            for _, column in ipairs(segment.columns) do
                local origin = { x = left, y = columns_top }
                draw_column_header(elements, column, origin, images, sizes, metrics)
                draw_column_cells(
                    elements,
                    column,
                    { x = left, y = columns_top + metrics.header_height },
                    images,
                    sizes,
                    metrics
                )
                left = left + metrics.column_width + COLUMN_GAP
            end
            left = left - COLUMN_GAP + (segment_index < #segments and GROUP_GAP or 0)
        end
        width = math.max(width, left + PADDING)
        top = columns_top + metrics.header_height + most_cells * metrics.cell_height
        if line_index < #lines then
            top = top + LINE_GAP
        end
    end
    return elements, { w = width, h = top + PADDING }
end

---@param view SwitchView
---@param images SwitchImages
---@param sizes SwitchSizes
---@param line_count integer the lines of the columns, which the rows do not use
---@return table[] elements
---@return table size the w and h of the list
local function draw(view, images, sizes, line_count)
    if view.lines then
        return draw_rows(view.lines, images, sizes)
    end
    return draw_columns(view.groups, images, sizes, line_count)
end

---@param relative_sizes SwitchRelativeSizes
---@param screen table the frame of the screen in front
---@param scale number
---@return SwitchSizes the sizes of the settings in points, times the scale
local function scale_sizes(relative_sizes, screen, scale)
    return create_sizes({
        w = relative_sizes.preview_size.w * screen.w * scale,
        h = relative_sizes.preview_size.h * screen.h * scale,
    }, relative_sizes.font_size * screen.h * math.min(scale, MAX_FONT_SCALE))
end

---The largest scale up to the limit at which the list fits within the screen.
---Each round shrinks the scale by the share by which the list is too large, and the paddings,
---which do not scale, need a few rounds.
---@param view SwitchView
---@param images SwitchImages
---@param relative_sizes SwitchRelativeSizes
---@param screen table
---@param max_scale number
---@param line_count integer
---@return number scale
---@return SwitchSizes sizes
local function find_largest_scale(view, images, relative_sizes, screen, max_scale, line_count)
    local scale = max_scale
    local sizes = scale_sizes(relative_sizes, screen, scale)
    for _ = 1, FIT_ROUNDS do
        local _, size = draw(view, images, sizes, line_count)
        local share =
            math.max(size.w / (MAX_WIDTH_SHARE * screen.w), size.h / (MAX_HEIGHT_SHARE * screen.h))
        if share <= 1 then
            return scale, sizes
        end
        scale = scale / share
        sizes = scale_sizes(relative_sizes, screen, scale)
    end
    return scale, sizes
end

---@param view SwitchView
---@return integer the number of columns of the view, or 0 for the rows
local function count_columns(view)
    local count = 0
    for _, group in ipairs(view.groups or {}) do
        count = count + #group.columns
    end
    return count
end

---Chooses the sizes and the number of lines that give the largest previews within the screen.
---Under fill_screen the previews may grow up to MAX_FILL_SCALE times the setting, and under fixed
---they keep the setting at most.
---A second line wins only when it makes the previews larger by REQUIRED_GAIN_OF_ANOTHER_LINE.
---@param view SwitchView
---@param images SwitchImages
---@param relative_sizes SwitchRelativeSizes
---@param screen table the frame of the screen in front
---@return SwitchSizes sizes
---@return integer line_count
local function fit_sizes(view, images, relative_sizes, screen)
    local max_scale = relative_sizes.sizing == list_sizing.FILL_SCREEN and MAX_FILL_SCALE or 1
    local most_lines = math.min(MAX_LINE_COUNT, math.max(1, count_columns(view)))
    local best_scale, best_sizes, best_line_count = nil, nil, 1
    for line_count = 1, most_lines do
        local scale, sizes =
            find_largest_scale(view, images, relative_sizes, screen, max_scale, line_count)
        if not best_scale or scale > best_scale * REQUIRED_GAIN_OF_ANOTHER_LINE then
            best_scale, best_sizes, best_line_count = scale, sizes, line_count
        end
    end
    return best_sizes, best_line_count
end

---@param size table the w and h of the list
---@return table the frame that centers the list on the screen in front
local function center_on_screen(size)
    local screen = hs.screen.mainScreen():frame()
    return {
        x = screen.x + (screen.w - size.w) / 2,
        y = screen.y + (screen.h - size.h) / 2,
        w = size.w,
        h = size.h,
    }
end

---@param view SwitchView
---@param images SwitchImages
---@param relative_sizes SwitchRelativeSizes
---@return SwitchOverlay
function switch_overlay.show(view, images, relative_sizes)
    local sizes, line_count =
        fit_sizes(view, images, relative_sizes, hs.screen.mainScreen():frame())
    local elements, size = draw(view, images, sizes, line_count)
    local canvas = hs.canvas.new(center_on_screen(size))
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:replaceElements(elements)
    canvas:show()
    return { canvas = canvas, sizes = sizes, line_count = line_count }
end

---@param overlay SwitchOverlay
---@param view SwitchView
---@param images SwitchImages
function switch_overlay.update(overlay, view, images)
    local elements, size = draw(view, images, overlay.sizes, overlay.line_count)
    overlay.canvas:frame(center_on_screen(size))
    overlay.canvas:replaceElements(elements)
end

---@param overlay SwitchOverlay
---@return table the w and h of a preview in points, which the snapshots render for
function switch_overlay.read_preview_size(overlay)
    return overlay.sizes.preview_size
end

---@param overlay SwitchOverlay
function switch_overlay.hide(overlay)
    overlay.canvas:delete()
end

return switch_overlay
