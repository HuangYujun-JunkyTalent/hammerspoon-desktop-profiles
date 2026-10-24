local enumeration = require("desktop_manager.core.enumeration")

---What the list does with a title of a window that is longer than its space.
---`TRUNCATE` shortens the title to one line and ends it in an ellipsis.
---`WRAP` lets the title flow over several lines, up to the setting title_line_count.
---`SCROLL` scrolls the title of the selected window, and shortens the other titles.
local title_overflow = enumeration.define({
    TRUNCATE = "truncate",
    WRAP = "wrap",
    SCROLL = "scroll",
})

---@alias TitleOverflow "truncate"|"wrap"|"scroll"

return title_overflow
