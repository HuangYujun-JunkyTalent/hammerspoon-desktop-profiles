---The list that a press of Control-Option with a number shows: the numbered applications of the
---active profile, the titles of their windows, and the selected window.
local switch_list = {}

---@class SwitchWindow
---@field window_id integer
---@field title string
---@field screen_uuid string|nil the display of the window, when its desktop is known

---An application of the list, with its windows in the order of the presses.
---@class SwitchApplication
---@field number integer
---@field bundle_id string
---@field app_name string
---@field windows SwitchWindow[]
---@field first_window_index integer the window that the first press selects, 0 without windows

---The selected window, or the application itself when it has no window.
---@class SwitchSelection
---@field number integer
---@field window_index integer 0 when the application has no window

---@class SwitchLine
---@field text string
---@field is_application boolean
---@field is_selected boolean
---@field bundle_id string the application of the line, whose icon the line shows
---@field window_id integer|nil the window of the line, whose preview the line shows

---A window of a column, with the title that the overlay shortens to the width of the column.
---@class SwitchCell
---@field window_id integer
---@field title string
---@field is_selected boolean

---An application of the columns, with the windows that the column holds.
---@class SwitchColumn
---@field number integer
---@field app_name string
---@field bundle_id string
---@field is_selected boolean whether the application itself is selected, because it has no window
---@field cells SwitchCell[]

---The columns of one display, or of no display for the windows elsewhere and the applications
---without windows.
---@class SwitchColumnGroup
---@field display_name string|nil
---@field columns SwitchColumn[]

---@class SwitchDisplay
---@field screen_uuid string
---@field name string

local ELLIPSIS = "…"
local UNTITLED = "untitled window"
local WINDOW_INDENT = "      "

---@param applications SwitchApplication[]
---@param number integer
---@return SwitchApplication|nil
function switch_list.find_application(applications, number)
    for _, application in ipairs(applications) do
        if application.number == number then
            return application
        end
    end
    return nil
end

---Moves the selection for a press of the number.
---Another press of the selected number selects the next window of its application.
---A press of another number selects the first window of that application.
---A number without an application leaves the selection as it is.
---@param applications SwitchApplication[]
---@param selection SwitchSelection|nil
---@param number integer
---@return SwitchSelection|nil
function switch_list.press(applications, selection, number)
    local application = switch_list.find_application(applications, number)
    if not application then
        return selection
    end
    local window_count = #application.windows
    if selection and selection.number == number and window_count > 0 then
        return { number = number, window_index = selection.window_index % window_count + 1 }
    end
    return { number = number, window_index = application.first_window_index }
end

---@param applications SwitchApplication[]
---@param selection SwitchSelection|nil
---@return integer|nil the id of the selected window, or nil when the application has no window
function switch_list.find_selected_window_id(applications, selection)
    local application = selection and switch_list.find_application(applications, selection.number)
    local window = application and application.windows[selection.window_index]
    return window and window.window_id or nil
end

---@param title string
---@param max_length integer the most characters that a title keeps, the ellipsis included
---@return string
function switch_list.shorten(title, max_length)
    local is_valid, length = pcall(utf8.len, title)
    if not is_valid or not length then
        return title:sub(1, max_length)
    end
    if length <= max_length then
        return title
    end
    return title:sub(1, utf8.offset(title, max_length) - 1) .. ELLIPSIS
end

---The lines of the list: each application with its number, and under it the titles of its windows.
---@param applications SwitchApplication[]
---@param selection SwitchSelection|nil
---@param max_title_length integer
---@return SwitchLine[]
function switch_list.describe_lines(applications, selection, max_title_length)
    local lines = {}
    for _, application in ipairs(applications) do
        local is_selected_application = selection ~= nil and selection.number == application.number
        table.insert(lines, {
            text = string.format("%d   %s", application.number, application.app_name),
            is_application = true,
            is_selected = is_selected_application and selection.window_index == 0,
            bundle_id = application.bundle_id,
        })
        if #application.windows == 0 then
            table.insert(lines, {
                text = WINDOW_INDENT .. "no window, a new one opens",
                is_application = false,
                is_selected = false,
                bundle_id = application.bundle_id,
            })
        end
        for index, window in ipairs(application.windows) do
            local title = window.title ~= "" and window.title or UNTITLED
            table.insert(lines, {
                text = WINDOW_INDENT .. switch_list.shorten(title, max_title_length),
                is_application = false,
                is_selected = is_selected_application and selection.window_index == index,
                bundle_id = application.bundle_id,
                window_id = window.window_id,
            })
        end
    end
    return lines
end

---@param application SwitchApplication
---@param selection SwitchSelection|nil
---@param is_in_column fun(window: SwitchWindow): boolean
---@return SwitchColumn
local function build_column(application, selection, is_in_column)
    local is_selected_application = selection ~= nil and selection.number == application.number
    local cells = {}
    for index, window in ipairs(application.windows) do
        if is_in_column(window) then
            table.insert(cells, {
                window_id = window.window_id,
                title = window.title ~= "" and window.title or UNTITLED,
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
    }
end

---@param window SwitchWindow
---@return boolean
local function is_any_window(window)
    return window ~= nil
end

---One column per application, with all its windows.
---@param applications SwitchApplication[]
---@param selection SwitchSelection|nil
---@return SwitchColumnGroup[]
function switch_list.describe_application_columns(applications, selection)
    local columns = {}
    for _, application in ipairs(applications) do
        table.insert(columns, build_column(application, selection, is_any_window))
    end
    return { { display_name = nil, columns = columns } }
end

---One group of columns per display that holds a window of the list, in the order of the displays.
---A last group without a display holds the windows whose display is unknown, and the applications
---without windows.
---@param applications SwitchApplication[]
---@param selection SwitchSelection|nil
---@param displays SwitchDisplay[] in the order in which the displays stand from left to right
---@return SwitchColumnGroup[]
function switch_list.describe_display_columns(applications, selection, displays)
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

return switch_list
