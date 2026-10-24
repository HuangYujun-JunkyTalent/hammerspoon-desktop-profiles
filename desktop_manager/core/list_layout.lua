local enumeration = require("desktop_manager.core.enumeration")

---How the list of numbered applications arranges the applications and their windows.
---`ROWS` stacks each application and its windows in one column of lines.
---`COLUMNS` gives each application a column, with its windows stacked downward.
---`COLUMNS_PER_DISPLAY` groups the columns by display, so an application has a column for each
---display that holds one of its windows.
local list_layout = enumeration.define({
    ROWS = "rows",
    COLUMNS = "columns",
    COLUMNS_PER_DISPLAY = "columns_per_display",
})

---@alias ListLayout "rows"|"columns"|"columns_per_display"

return list_layout
