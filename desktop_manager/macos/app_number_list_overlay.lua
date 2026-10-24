local app_number_list_view = require("desktop_manager.core.app_number_list_view")
local canvas_elements = require("desktop_manager.macos.canvas_elements")
local list_sizing = require("desktop_manager.core.list_sizing")
local retained_timers = require("desktop_manager.macos.retained_timers")
local title_overflow = require("desktop_manager.core.title_overflow")
local utf8_text = require("desktop_manager.core.utf8_text")

---Draws the list of numbered applications and their windows in the middle of the screen in front,
---as rows of lines or as columns of applications.
local app_number_list_overlay = {}

app_number_list_overlay.MAX_TITLE_LENGTH = 60

---The images that the list and the search show: the icon of each application, and the preview of
---each window that has one.
---@class IconsAndPreviews
---@field app_icons table<string, table> the hs.image of each bundle id
---@field previews table<integer, table> the hs.image of each window id

---What the list shows: lines for the rows, or groups of columns.
---@class AppNumberListView
---@field lines AppNumberListLine[]|nil
---@field groups AppNumberListColumnGroup[]|nil

---The settings of the list: its sizes as fractions of the screen in front, and its titles.
---@class AppNumberListSettings
---@field preview_size table the w and h of a preview, as fractions of the width and height
---@field font_size number the size of the titles, as a fraction of the height
---@field sizing string a value of list_sizing
---@field title_overflow string a value of title_overflow
---@field title_line_count integer the most lines of a title under title_overflow wrap

---The sizes of the list in points, which the fit to the screen chose.
---@class AppNumberListSizes
---@field preview_size table the w and h of a preview in points
---@field font_size number the size of the titles in points
---@field application_font_size number
---@field icon_size number
---@field text_height number the height of a line of an application name
---@field title_height number the height of a line of a title

---The title that scrolls: the index of its text element, the title and the characters it shows.
---@class ScrollingTitle
---@field element_index integer
---@field title string
---@field visible_count integer

---What a drawing of the list reads.
---@class DrawingContext
---@field images IconsAndPreviews
---@field sizes AppNumberListSizes
---@field line_count integer the lines of the columns, which the rows do not use
---@field settings AppNumberListSettings

---A list on the screen: its canvas, its sizes in points, the number of lines of its columns, and
---the timers of a scrolling title.
---@class AppNumberListOverlay
---@field canvas table an hs.canvas
---@field sizes AppNumberListSizes
---@field line_count integer
---@field settings AppNumberListSettings
---@field scroll_timers table[]

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
local SCROLL_PAUSE_SECONDS = 1
local SCROLL_STEP_SECONDS = 0.15
local BACKGROUND_COLOR = { white = 0.12, alpha = 0.92 }
local SELECTION_COLOR = { red = 0.2, green = 0.45, blue = 0.95, alpha = 0.95 }
local TEXT_COLOR = { white = 1, alpha = 1 }
local DIMMED_TEXT_COLOR = { white = 0.75, alpha = 1 }

---@param preview_size table the w and h of a preview in points
---@param font_size number the size of the titles in points
---@return AppNumberListSizes
local function create_sizes(preview_size, font_size)
    local application_font_size = font_size + 2
    return {
        preview_size = { w = preview_size.w, h = preview_size.h },
        font_size = font_size,
        application_font_size = application_font_size,
        icon_size = math.floor(application_font_size * LINE_HEIGHT_PER_POINT + 0.5),
        text_height = math.ceil(application_font_size * LINE_HEIGHT_PER_POINT),
        title_height = math.ceil(font_size * LINE_HEIGHT_PER_POINT),
    }
end

---@param width number in points
---@param font_size number in points
---@return integer the characters of a title that fit the width
local function count_fitting_characters(width, font_size)
    return math.max(4, math.floor(width / (font_size * CHARACTER_WIDTH_PER_POINT)))
end

---A title laid out for its space: the text to draw, its lines, and whether it scrolls.
---@class TitleLayout
---@field text string
---@field line_count integer
---@field is_scrolling boolean

---@param title string
---@param visible_count integer the characters that one line holds
---@return TitleLayout
local function truncate_title(title, visible_count)
    return {
        text = utf8_text.shorten(title, visible_count),
        line_count = 1,
        is_scrolling = false,
    }
end

local TITLE_LAYOUTS = {
    [title_overflow.TRUNCATE] = truncate_title,
    [title_overflow.WRAP] = function(title, visible_count, _, line_limit)
        local needed = math.ceil(utf8_text.count_characters(title) / visible_count)
        return {
            text = utf8_text.shorten(title, visible_count * line_limit),
            line_count = math.max(1, math.min(line_limit, needed)),
            is_scrolling = false,
        }
    end,
    [title_overflow.SCROLL] = function(title, visible_count, is_selected)
        if not is_selected or utf8_text.count_characters(title) <= visible_count then
            return truncate_title(title, visible_count)
        end
        return {
            text = app_number_list_view.scroll_title(title, 0, visible_count),
            line_count = 1,
            is_scrolling = true,
        }
    end,
}

---@param title string
---@param visible_count integer the characters that one line holds
---@param is_selected boolean
---@param settings AppNumberListSettings
---@return TitleLayout
local function lay_out_title(title, visible_count, is_selected, settings)
    return TITLE_LAYOUTS[settings.title_overflow](
        title,
        visible_count,
        is_selected,
        settings.title_line_count
    )
end

---@param sizes AppNumberListSizes
---@param preview table|nil the hs.image of the preview of a window
---@return table the w and h of the preview when there is one, and of an icon otherwise
local function choose_image_size(sizes, preview)
    return preview and sizes.preview_size or { w = sizes.icon_size, h = sizes.icon_size }
end

---@class TextStyle
---@field font_size number
---@field is_bold boolean
---@field is_bright boolean

---@param text string
---@param frame table
---@param style TextStyle
---@return table a text element, which wraps at words when its frame holds several lines
local function build_text(text, frame, style)
    return {
        type = "text",
        text = text,
        textFont = style.is_bold and "Helvetica-Bold" or "Helvetica",
        textSize = style.font_size,
        textColor = style.is_bright and TEXT_COLOR or DIMMED_TEXT_COLOR,
        textLineBreak = "wordWrap",
        frame = frame,
    }
end

---@param frame table
---@return table a rectangle element behind a selected line or cell
local function build_selection(frame)
    return canvas_elements.build_rounded_rectangle(
        frame,
        SELECTION_COLOR,
        canvas_elements.BACKDROP_RADIUS,
        "selection"
    )
end

---@return table the rectangle element of the background
local function build_background()
    return canvas_elements.build_rounded_rectangle(
        nil,
        BACKGROUND_COLOR,
        canvas_elements.BACKGROUND_RADIUS,
        nil
    )
end

---Adds the text element of a title, and returns the scrolling title when it scrolls.
---@param elements table[]
---@param title string
---@param layout TitleLayout
---@param frame table
---@param style TextStyle
---@param visible_count integer
---@return ScrollingTitle|nil
local function add_title(elements, title, layout, frame, style, visible_count)
    table.insert(elements, build_text(layout.text, frame, style))
    if not layout.is_scrolling then
        return nil
    end
    return { element_index = #elements, title = title, visible_count = visible_count }
end

---The sizes in points that the rows derive from the sizes of the list.
---@class RowMetrics
---@field application_line_height number
---@field preview_inset number the left edge of a preview
---@field window_text_inset number the left edge of the title of a window
---@field application_text_inset number the left edge of the name of an application
---@field width number the width of the list
---@field visible_count integer the characters of a title that one line holds

---@param sizes AppNumberListSizes
---@return RowMetrics
local function measure_rows(sizes)
    local preview_inset = PADDING + GAP
    local window_text_inset = preview_inset + sizes.preview_size.w + GAP
    local title_width = math.floor(
        app_number_list_overlay.MAX_TITLE_LENGTH * sizes.font_size * CHARACTER_WIDTH_PER_POINT + 0.5
    )
    return {
        application_line_height = math.max(sizes.icon_size, sizes.text_height) + 8,
        preview_inset = preview_inset,
        window_text_inset = window_text_inset,
        application_text_inset = PADDING + sizes.icon_size + 10,
        width = window_text_inset + title_width + PADDING,
        visible_count = count_fitting_characters(title_width, sizes.font_size),
    }
end

---Draws one line of the rows, an application or a window with its preview, from its top.
---@param elements table[]
---@param line AppNumberListLine
---@param top number
---@param context DrawingContext
---@param metrics RowMetrics
---@return number the height of the line
---@return ScrollingTitle|nil
local function draw_row_line(elements, line, top, context, metrics)
    local sizes, images = context.sizes, context.images
    local width, visible_count = metrics.width, metrics.visible_count
    local text = line.is_application and line.text or (line.text:gsub("^%s+", ""))
    local layout = { text = text, line_count = 1, is_scrolling = false }
    if not line.is_application and line.window_id then
        layout = lay_out_title(text, visible_count, line.is_selected, context.settings)
    end
    local text_height = line.is_application and sizes.text_height
        or layout.line_count * sizes.title_height
    local height = line.is_application and metrics.application_line_height
        or math.max(sizes.preview_size.h, text_height) + 7
    if line.is_selected then
        table.insert(
            elements,
            build_selection({ x = PADDING / 2, y = top, w = width - PADDING, h = height })
        )
    end
    local preview = line.window_id and images.previews[line.window_id]
    local box = { x = metrics.preview_inset, y = top, w = sizes.preview_size.w, h = height }
    if line.is_application then
        box = { x = PADDING, y = top, w = sizes.icon_size, h = height }
    end
    local image = canvas_elements.build_centered_image(
        preview or images.app_icons[line.bundle_id],
        box,
        choose_image_size(sizes, preview),
        nil
    )
    if image then
        table.insert(elements, image)
    end
    local inset = line.is_application and metrics.application_text_inset
        or metrics.window_text_inset
    local scrolling = add_title(elements, text, layout, {
        x = inset,
        y = top + (height - text_height) / 2,
        w = width - inset - PADDING,
        h = text_height,
    }, {
        font_size = line.is_application and sizes.application_font_size or sizes.font_size,
        is_bold = line.is_application,
        is_bright = line.is_application or line.is_selected,
    }, visible_count)
    return height, scrolling
end

---Draws the rows: each application on a line, and under it a line per window with its preview.
---@param lines AppNumberListLine[]
---@param context DrawingContext
---@return table[] elements
---@return table size the w and h of the list
---@return ScrollingTitle|nil
local function draw_rows(lines, context)
    local metrics = measure_rows(context.sizes)
    local elements, scrolling = { build_background() }, nil
    local top = PADDING
    for _, line in ipairs(lines) do
        local height, line_scrolling = draw_row_line(elements, line, top, context, metrics)
        scrolling = line_scrolling or scrolling
        top = top + height
    end
    return elements, { w = metrics.width, h = top + PADDING }, scrolling
end

---The sizes in points that the columns derive from the sizes of the list.
---@class ColumnMetrics
---@field header_height number
---@field column_width number
---@field title_width number
---@field visible_count integer the characters of a title that one line holds

---@param sizes AppNumberListSizes
---@return ColumnMetrics
local function measure_columns(sizes)
    local column_width = math.max(
        sizes.preview_size.w,
        HEADER_CHARACTERS * sizes.application_font_size
    ) + 2 * CELL_PADDING
    local title_width = column_width - 2 * CELL_PADDING
    return {
        header_height = math.max(sizes.icon_size, sizes.text_height) + 8,
        column_width = column_width,
        title_width = title_width,
        visible_count = count_fitting_characters(title_width, sizes.font_size),
    }
end

---Draws the header of a column: the icon, the number and the name of the application.
---@param elements table[]
---@param column AppNumberListColumn
---@param origin table the x and y of the column
---@param context DrawingContext
---@param metrics ColumnMetrics
local function draw_column_header(elements, column, origin, context, metrics)
    local sizes = context.sizes
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
    local icon = canvas_elements.build_centered_image(context.images.app_icons[column.bundle_id], {
        x = origin.x + CELL_PADDING,
        y = origin.y,
        w = sizes.icon_size,
        h = metrics.header_height,
    }, choose_image_size(sizes, nil), nil)
    if icon then
        table.insert(elements, icon)
    end
    local inset = CELL_PADDING + sizes.icon_size + 6
    local width = metrics.column_width - inset - CELL_PADDING
    local text = utf8_text.shorten(
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

---Draws one window of a column, a preview with its title under it, from the top of its cell.
---@param elements table[]
---@param column AppNumberListColumn
---@param cell AppNumberListCell
---@param origin table the x of the column and the y of the top of the cell
---@param context DrawingContext
---@param metrics ColumnMetrics
---@return number the height of the cell
---@return ScrollingTitle|nil
local function draw_column_cell(elements, column, cell, origin, context, metrics)
    local sizes = context.sizes
    local top = origin.y
    local layout =
        lay_out_title(cell.title, metrics.visible_count, cell.is_selected, context.settings)
    local title_height = layout.line_count * sizes.title_height
    local cell_height = sizes.preview_size.h + title_height + 3 * CELL_PADDING / 2
    if cell.is_selected then
        table.insert(
            elements,
            build_selection({
                x = origin.x,
                y = top,
                w = metrics.column_width,
                h = cell_height,
            })
        )
    end
    local preview = context.images.previews[cell.window_id]
    local icon = context.images.app_icons[column.bundle_id]
    local image = canvas_elements.build_centered_image(preview or icon, {
        x = origin.x + CELL_PADDING,
        y = top + CELL_PADDING / 2,
        w = metrics.title_width,
        h = sizes.preview_size.h,
    }, choose_image_size(sizes, preview), nil)
    if image then
        table.insert(elements, image)
    end
    local scrolling = add_title(elements, cell.title, layout, {
        x = origin.x + CELL_PADDING,
        y = top + CELL_PADDING + sizes.preview_size.h,
        w = metrics.title_width,
        h = title_height,
    }, {
        font_size = sizes.font_size,
        is_bold = false,
        is_bright = cell.is_selected,
    }, metrics.visible_count)
    return cell_height, scrolling
end

---Draws the windows of a column downward, each a preview with its title under it.
---@param elements table[]
---@param column AppNumberListColumn
---@param origin table the x and y of the first cell
---@param context DrawingContext
---@param metrics ColumnMetrics
---@return number the height of the cells
---@return ScrollingTitle|nil
local function draw_column_cells(elements, column, origin, context, metrics)
    local sizes = context.sizes
    if #column.cells == 0 then
        table.insert(
            elements,
            build_text(utf8_text.shorten(column.note or "", metrics.visible_count), {
                x = origin.x + CELL_PADDING,
                y = origin.y + CELL_PADDING,
                w = metrics.title_width,
                h = sizes.title_height,
            }, { font_size = sizes.font_size, is_bold = false, is_bright = false })
        )
        return sizes.title_height + 2 * CELL_PADDING, nil
    end
    local top, scrolling = origin.y, nil
    for _, cell in ipairs(column.cells) do
        local cell_height, cell_scrolling =
            draw_column_cell(elements, column, cell, { x = origin.x, y = top }, context, metrics)
        scrolling = cell_scrolling or scrolling
        top = top + cell_height
    end
    return top - origin.y, scrolling
end

---A run of columns of one group on one line of the list.
---@class ColumnSegment
---@field display_name string|nil
---@field columns AppNumberListColumn[]

---Folds the columns into lines, the first lines taking the larger share, so the numbers read from
---left to right and then downward.
---A group of a display that continues on the next line starts a new segment there.
---@param groups AppNumberListColumnGroup[]
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

---Draws the name of the display of a segment above its columns.
---@param elements table[]
---@param segment ColumnSegment
---@param origin table the x and y of the label
---@param sizes AppNumberListSizes
---@param metrics ColumnMetrics
local function draw_display_label(elements, segment, origin, sizes, metrics)
    local segment_width = #segment.columns * (metrics.column_width + COLUMN_GAP) - COLUMN_GAP
    table.insert(
        elements,
        build_text(
            segment.display_name,
            { x = origin.x, y = origin.y, w = segment_width, h = sizes.title_height },
            { font_size = sizes.font_size, is_bold = false, is_bright = false }
        )
    )
end

---Draws the columns: a column per application with its windows stacked downward, the name of a
---display above its columns, and the columns folded into the lines of the context.
---@param groups AppNumberListColumnGroup[]
---@param context DrawingContext
---@return table[] elements
---@return table size the w and h of the list
---@return ScrollingTitle|nil
local function draw_columns(groups, context)
    local sizes = context.sizes
    local metrics = measure_columns(sizes)
    local has_display_names = false
    for _, group in ipairs(groups) do
        has_display_names = has_display_names or group.display_name ~= nil
    end
    local label_height = has_display_names and sizes.title_height + 6 or 0
    local elements, scrolling = { build_background() }, nil
    local top, width = PADDING, 0
    local lines = fold_columns(groups, context.line_count)
    for line_index, segments in ipairs(lines) do
        local columns_top = top + label_height
        local cells_top = columns_top + metrics.header_height
        local tallest_cells = 0
        local left = PADDING
        for segment_index, segment in ipairs(segments) do
            if segment.display_name then
                draw_display_label(elements, segment, { x = left, y = top }, sizes, metrics)
            end
            for _, column in ipairs(segment.columns) do
                draw_column_header(
                    elements,
                    column,
                    { x = left, y = columns_top },
                    context,
                    metrics
                )
                local cells_height, column_scrolling = draw_column_cells(
                    elements,
                    column,
                    { x = left, y = cells_top },
                    context,
                    metrics
                )
                tallest_cells = math.max(tallest_cells, cells_height)
                scrolling = column_scrolling or scrolling
                left = left + metrics.column_width + COLUMN_GAP
            end
            left = left - COLUMN_GAP + (segment_index < #segments and GROUP_GAP or 0)
        end
        width = math.max(width, left + PADDING)
        top = cells_top + tallest_cells
        if line_index < #lines then
            top = top + LINE_GAP
        end
    end
    return elements, { w = width, h = top + PADDING }, scrolling
end

---@param view AppNumberListView
---@param context DrawingContext
---@return table[] elements
---@return table size the w and h of the list
---@return ScrollingTitle|nil
local function draw_list(view, context)
    if view.lines then
        return draw_rows(view.lines, context)
    end
    return draw_columns(view.groups, context)
end

---@param settings AppNumberListSettings
---@param screen table the frame of the screen in front
---@param scale number
---@return AppNumberListSizes the sizes of the settings in points, times the scale
local function scale_sizes(settings, screen, scale)
    return create_sizes({
        w = settings.preview_size.w * screen.w * scale,
        h = settings.preview_size.h * screen.h * scale,
    }, settings.font_size * screen.h * math.min(scale, MAX_FONT_SCALE))
end

---The largest scale up to the limit at which the list fits within the screen.
---Each round shrinks the scale by the share by which the list is too large, and the paddings,
---which do not scale, need a few rounds.
---@param view AppNumberListView
---@param context DrawingContext the images, the settings and the lines; the sizes are replaced
---@param screen table
---@param max_scale number
---@return number scale
---@return AppNumberListSizes sizes
local function find_largest_scale(view, context, screen, max_scale)
    local scale = max_scale
    local trial = {
        images = context.images,
        settings = context.settings,
        line_count = context.line_count,
        sizes = scale_sizes(context.settings, screen, scale),
    }
    for _ = 1, FIT_ROUNDS do
        local _, size = draw_list(view, trial)
        local share =
            math.max(size.w / (MAX_WIDTH_SHARE * screen.w), size.h / (MAX_HEIGHT_SHARE * screen.h))
        if share <= 1 then
            return scale, trial.sizes
        end
        scale = scale / share
        trial.sizes = scale_sizes(context.settings, screen, scale)
    end
    return scale, trial.sizes
end

---@param view AppNumberListView
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
---@param view AppNumberListView
---@param images IconsAndPreviews
---@param settings AppNumberListSettings
---@param screen table the frame of the screen in front
---@return DrawingContext
local function fit_to_screen(view, images, settings, screen)
    local max_scale = settings.sizing == list_sizing.FILL_SCREEN and MAX_FILL_SCALE or 1
    local most_lines = math.min(MAX_LINE_COUNT, math.max(1, count_columns(view)))
    local best_scale, best_context = nil, nil
    for line_count = 1, most_lines do
        local context = { images = images, settings = settings, line_count = line_count }
        local scale, sizes = find_largest_scale(view, context, screen, max_scale)
        if not best_scale or scale > best_scale * REQUIRED_GAIN_OF_ANOTHER_LINE then
            context.sizes = sizes
            best_scale, best_context = scale, context
        end
    end
    return best_context
end

---@param overlay AppNumberListOverlay
local function stop_scrolling(overlay)
    for _, timer in ipairs(overlay.scroll_timers) do
        retained_timers.stop(timer)
    end
    overlay.scroll_timers = {}
end

---Scrolls the title after a pause, one character per step, until the list changes or closes.
---@param overlay AppNumberListOverlay
---@param scrolling ScrollingTitle|nil
local function start_scrolling(overlay, scrolling)
    stop_scrolling(overlay)
    if not scrolling then
        return
    end
    local step = 0
    table.insert(
        overlay.scroll_timers,
        retained_timers.after(SCROLL_PAUSE_SECONDS, function()
            table.insert(
                overlay.scroll_timers,
                retained_timers.every(SCROLL_STEP_SECONDS, function()
                    step = step + 1
                    overlay.canvas:elementAttribute(
                        scrolling.element_index,
                        "text",
                        app_number_list_view.scroll_title(
                            scrolling.title,
                            step,
                            scrolling.visible_count
                        )
                    )
                end)
            )
        end)
    )
end

---@param view AppNumberListView
---@param images IconsAndPreviews
---@param settings AppNumberListSettings
---@return AppNumberListOverlay
function app_number_list_overlay.show(view, images, settings)
    local context = fit_to_screen(view, images, settings, hs.screen.mainScreen():frame())
    local elements, size, scrolling = draw_list(view, context)
    local canvas = hs.canvas.new(canvas_elements.center_on_screen(size))
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:replaceElements(elements)
    canvas:show()
    local overlay = {
        canvas = canvas,
        sizes = context.sizes,
        line_count = context.line_count,
        settings = settings,
        scroll_timers = {},
    }
    start_scrolling(overlay, scrolling)
    return overlay
end

---@param overlay AppNumberListOverlay
---@param view AppNumberListView
---@param images IconsAndPreviews
function app_number_list_overlay.update(overlay, view, images)
    local elements, size, scrolling = draw_list(view, {
        images = images,
        sizes = overlay.sizes,
        line_count = overlay.line_count,
        settings = overlay.settings,
    })
    overlay.canvas:frame(canvas_elements.center_on_screen(size))
    overlay.canvas:replaceElements(elements)
    start_scrolling(overlay, scrolling)
end

---@param overlay AppNumberListOverlay
---@return table the w and h of a preview in points, which the snapshots render for
function app_number_list_overlay.read_preview_size(overlay)
    return overlay.sizes.preview_size
end

---@param overlay AppNumberListOverlay
function app_number_list_overlay.hide(overlay)
    stop_scrolling(overlay)
    overlay.canvas:delete()
end

return app_number_list_overlay
