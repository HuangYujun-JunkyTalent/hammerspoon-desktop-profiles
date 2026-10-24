local enumeration = require("desktop_manager.core.enumeration")

---What a switch does for a recorded window whose window id no longer exists.
---`OPEN_NEW_WINDOW` opens a new window of the same application.
---`MATCH_TITLE_OR_OPEN_NEW_WINDOW` takes an open window of the same application with the same
---title, and opens a new window when no title matches.
local missing_window_policy = enumeration.define({
    OPEN_NEW_WINDOW = "open_new_window",
    MATCH_TITLE_OR_OPEN_NEW_WINDOW = "match_title_or_open_new_window",
})

---@alias MissingWindowPolicy "open_new_window"|"match_title_or_open_new_window"

return missing_window_policy
