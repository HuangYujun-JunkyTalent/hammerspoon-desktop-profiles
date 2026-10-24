local enumeration = require("desktop_manager.core.enumeration")

---What a switch tries first when it pairs a recorded window with an open window.
---`TITLE` takes the open window of the same application with the same title, the one with the
---recorded id first, and takes the window with the recorded id when no title matches, as for a
---browser window that shows another tab.
---`ID` takes the window with the recorded id, and takes a window with the same title when that
---window no longer exists, as `missing_window_policy` allows.
local match_windows_by = enumeration.define({
    TITLE = "title",
    ID = "id",
})

---@alias MatchWindowsBy "title"|"id"

return match_windows_by
