---The list that a press of Control-Option with a number shows: the numbered applications of the
---active profile, the titles of their windows, and the selected window.
local switch_list = {}

---@class SwitchWindow
---@field window_id integer
---@field title string

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

local ELLIPSIS = "…"
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
local function shorten(title, max_length)
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
            local title = window.title ~= "" and window.title or "untitled window"
            table.insert(lines, {
                text = WINDOW_INDENT .. shorten(title, max_title_length),
                is_application = false,
                is_selected = is_selected_application and selection.window_index == index,
                bundle_id = application.bundle_id,
                window_id = window.window_id,
            })
        end
    end
    return lines
end

return switch_list
