---The ways in which the list of Control-Option and the search treat the windows of hidden
---applications.
---`LEAVE_OUT` shows no window of a hidden application, on any desktop.
---`LIST_WHERE_FOUND` shows a window of a hidden application while the window filter holds it, while
---`allWindows` of the application gives it as a standard window, or while the list of the window
---server holds it on a desktop out of view.
---`LIST_ALL` also shows the windows that report another subrole while their application is hidden.
local hidden_application_windows = {
    LEAVE_OUT = "leave_out",
    LIST_WHERE_FOUND = "list_where_found",
    LIST_ALL = "list_all",
}

local VALID = {
    [hidden_application_windows.LEAVE_OUT] = true,
    [hidden_application_windows.LIST_WHERE_FOUND] = true,
    [hidden_application_windows.LIST_ALL] = true,
}

---@param value any
---@return boolean
function hidden_application_windows.is_valid(value)
    return VALID[value] == true
end

return hidden_application_windows
