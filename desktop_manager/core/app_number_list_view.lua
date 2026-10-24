local list_layout = require("desktop_manager.core.list_layout")
local utf8_text = require("desktop_manager.core.utf8_text")
local window_titles = require("desktop_manager.core.window_titles")

---The list that a press of Control-Option with a number shows: the numbered applications of the
---active profile, the titles of their windows, and the selected window.
local app_number_list_view = {}

---@class NumberedApplicationWindow
---@field window_id integer
---@field title string
---@field screen_uuid string|nil the display of the window, when its desktop is known

---An application of the list, with its windows in the order of the presses.
---@class NumberedApplication
---@field number integer
---@field bundle_id string
---@field app_name string
---@field windows NumberedApplicationWindow[]
---@field first_window_index integer the window that the first press selects, 0 without windows
---@field is_hidden boolean|nil true for a hidden application of which the list shows no window, so
---that a press unhides it

---The selected window, or the application itself when it has no window.
---@class AppNumberListSelection
---@field number integer
---@field window_index integer 0 when the application has no window

---@class AppNumberListLine
---@field text string
---@field is_application boolean
---@field is_selected boolean
---@field bundle_id string the application of the line, whose icon the line shows
---@field window_id integer|nil the window of the line, whose preview the line shows

---A window of a column, with the title that the overlay shortens to the width of the column.
---@class AppNumberListCell
---@field window_id integer
---@field title string
---@field is_selected boolean

---An application of the columns, with the windows that the column holds.
---@class AppNumberListColumn
---@field number integer
---@field app_name string
---@field bundle_id string
---@field is_selected boolean whether the application itself is selected, because it has no window
---@field cells AppNumberListCell[]
---@field note string|nil the note that the column shows in the place of windows

---The columns of one display, or of no display for the windows elsewhere and the applications
---without windows.
---@class AppNumberListColumnGroup
---@field display_name string|nil
---@field columns AppNumberListColumn[]

---@class AppNumberListDisplay
---@field screen_uuid string
---@field name string

local NO_WINDOW_NOTE = "no window, a new one opens"
local HIDDEN_NOTE = "hidden, a press unhides it"

---@param applications NumberedApplication[]
---@param number integer
---@return NumberedApplication|nil
function app_number_list_view.find_application(applications, number)
    for _, application in ipairs(applications) do
        if application.number == number then
            return application
        end
    end
    return nil
end

---The note that the list shows in the place of the windows of an application without windows.
---@param application NumberedApplication
---@return string|nil nil when the list shows windows of the application
function app_number_list_view.describe_note(application)
    if #application.windows > 0 then
        return nil
    end
    return application.is_hidden and HIDDEN_NOTE or NO_WINDOW_NOTE
end

---Moves the selection for a press of the number.
---Another press of the selected number selects the next window of its application.
---A press of another number selects the first window of that application.
---A number without an application leaves the selection as it is.
---@param applications NumberedApplication[]
---@param selection AppNumberListSelection|nil
---@param number integer
---@return AppNumberListSelection|nil
function app_number_list_view.press(applications, selection, number)
    local application = app_number_list_view.find_application(applications, number)
    if not application then
        return selection
    end
    local window_count = #application.windows
    if selection and selection.number == number and window_count > 0 then
        return { number = number, window_index = selection.window_index % window_count + 1 }
    end
    return { number = number, window_index = application.first_window_index }
end

---@param applications NumberedApplication[]
---@param selection AppNumberListSelection|nil
---@return integer|nil the id of the selected window, or nil when the application has no window
function app_number_list_view.find_selected_window_id(applications, selection)
    local application = selection
        and app_number_list_view.find_application(applications, selection.number)
    local window = application and application.windows[selection.window_index]
    return window and window.window_id or nil
end

local SCROLL_SPACER = "     "

---The part of a scrolling title that shows at a step: the title followed by a space, moved left by
---one character per step and starting again after its end.
---@param title string
---@param step integer 0 for the start of the title
---@param visible_count integer the characters that the space shows
---@return string
function app_number_list_view.scroll_title(title, step, visible_count)
    local characters = utf8_text.split_characters(title .. SCROLL_SPACER)
    local visible = {}
    for offset = 0, visible_count - 1 do
        table.insert(visible, characters[(step + offset) % #characters + 1])
    end
    return table.concat(visible)
end

---The lines of the list: each application with its number, and under it the titles of its windows.
---@param applications NumberedApplication[]
---@param selection AppNumberListSelection|nil
---@param max_title_length integer
---@return AppNumberListLine[]
function app_number_list_view.describe_lines(applications, selection, max_title_length)
    local lines = {}
    for _, application in ipairs(applications) do
        local is_selected_application = selection ~= nil and selection.number == application.number
        table.insert(lines, {
            text = string.format("%d   %s", application.number, application.app_name),
            is_application = true,
            is_selected = is_selected_application and selection.window_index == 0,
            bundle_id = application.bundle_id,
        })
        local note = app_number_list_view.describe_note(application)
        if note then
            table.insert(lines, {
                text = note,
                is_application = false,
                is_selected = false,
                bundle_id = application.bundle_id,
            })
        end
        for index, window in ipairs(application.windows) do
            table.insert(lines, {
                text = utf8_text.shorten(window_titles.describe(window.title), max_title_length),
                is_application = false,
                is_selected = is_selected_application and selection.window_index == index,
                bundle_id = application.bundle_id,
                window_id = window.window_id,
            })
        end
    end
    return lines
end

---@param application NumberedApplication
---@param selection AppNumberListSelection|nil
---@param is_in_column fun(window: NumberedApplicationWindow): boolean
---@return AppNumberListColumn
local function build_column(application, selection, is_in_column)
    local is_selected_application = selection ~= nil and selection.number == application.number
    local cells = {}
    for index, window in ipairs(application.windows) do
        if is_in_column(window) then
            table.insert(cells, {
                window_id = window.window_id,
                title = window_titles.describe(window.title),
                is_selected = is_selected_application and selection.window_index == index,
            })
        end
    end
    return {
        number = application.number,
        app_name = application.app_name,
        bundle_id = application.bundle_id,
        is_selected = is_selected_application and selection.window_index == 0,
        cells = cells,
        note = app_number_list_view.describe_note(application),
    }
end

---@param window NumberedApplicationWindow
---@return boolean
local function is_any_window(window)
    return window ~= nil
end

---One column per application, with all its windows.
---@param applications NumberedApplication[]
---@param selection AppNumberListSelection|nil
---@return AppNumberListColumnGroup[]
function app_number_list_view.describe_application_columns(applications, selection)
    local columns = {}
    for _, application in ipairs(applications) do
        table.insert(columns, build_column(application, selection, is_any_window))
    end
    return { { display_name = nil, columns = columns } }
end

---One group of columns per display that holds a window of the list, in the order of the displays.
---A last group without a display holds the windows whose display is unknown, and the applications
---without windows.
---@param applications NumberedApplication[]
---@param selection AppNumberListSelection|nil
---@param displays AppNumberListDisplay[] in the order in which the displays stand from left
---to right
---@return AppNumberListColumnGroup[]
function app_number_list_view.describe_display_columns(applications, selection, displays)
    local is_known_display = {}
    for _, display in ipairs(displays) do
        is_known_display[display.screen_uuid] = true
    end
    local groups = {}
    for _, display in ipairs(displays) do
        local columns = {}
        for _, application in ipairs(applications) do
            local column = build_column(application, selection, function(window)
                return window.screen_uuid == display.screen_uuid
            end)
            if #column.cells > 0 then
                column.is_selected = false
                table.insert(columns, column)
            end
        end
        if #columns > 0 then
            table.insert(groups, { display_name = display.name, columns = columns })
        end
    end
    local other_columns = {}
    for _, application in ipairs(applications) do
        local column = build_column(application, selection, function(window)
            return not is_known_display[window.screen_uuid]
        end)
        if #column.cells > 0 or #application.windows == 0 then
            table.insert(other_columns, column)
        end
    end
    if #other_columns > 0 then
        table.insert(groups, { display_name = nil, columns = other_columns })
    end
    return groups
end

---@param applications NumberedApplication[]
---@param selection AppNumberListSelection|nil
---@param _ AppNumberListDisplay[]
---@param max_title_length integer
---@return SwitchView
local function describe_rows(applications, selection, _, max_title_length)
    local lines = app_number_list_view.describe_lines(applications, selection, max_title_length)
    return { lines = lines }
end

---@param applications NumberedApplication[]
---@param selection AppNumberListSelection|nil
---@return SwitchView
local function describe_columns(applications, selection)
    return { groups = app_number_list_view.describe_application_columns(applications, selection) }
end

---@param applications NumberedApplication[]
---@param selection AppNumberListSelection|nil
---@param displays AppNumberListDisplay[]
---@return SwitchView
local function describe_columns_per_display(applications, selection, displays)
    return {
        groups = app_number_list_view.describe_display_columns(applications, selection, displays),
    }
end

local VIEW_BUILDERS = {
    [list_layout.ROWS] = describe_rows,
    [list_layout.COLUMNS] = describe_columns,
    [list_layout.COLUMNS_PER_DISPLAY] = describe_columns_per_display,
}

---@param layout string a value of the setting list_layout
---@param applications NumberedApplication[]
---@param selection AppNumberListSelection|nil
---@param displays AppNumberListDisplay[] the displays from left to right, for the columns per
---display
---@param max_title_length integer the longest title of a line, for the rows
---@return SwitchView the lines or the groups of columns that the list draws under the layout
function app_number_list_view.describe_view(
    layout,
    applications,
    selection,
    displays,
    max_title_length
)
    return VIEW_BUILDERS[layout](applications, selection, displays, max_title_length)
end

return app_number_list_view
