local enumeration = require("desktop_manager.core.enumeration")

---The ways in which the list of Control-Option and the search treat the windows of hidden
---applications.
---`LEAVE_OUT` shows no window of a hidden application, on any desktop.
---`LIST_WHERE_FOUND` shows a window of a hidden application while the window filter holds it, while
---`allWindows` of the application gives it as a standard window, or while the list of the window
---server holds it on a desktop out of view.
---`LIST_ALL` also shows the windows that report another subrole while their application is hidden.
local hidden_application_windows = enumeration.define({
    LEAVE_OUT = "leave_out",
    LIST_WHERE_FOUND = "list_where_found",
    LIST_ALL = "list_all",
})

---@alias HiddenApplicationWindows "leave_out"|"list_where_found"|"list_all"

return hidden_application_windows
