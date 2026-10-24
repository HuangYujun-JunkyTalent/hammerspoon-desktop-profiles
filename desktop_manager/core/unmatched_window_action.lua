local enumeration = require("desktop_manager.core.enumeration")

---What a switch does for a record in sight that found no open window to take, under either way of
---matching windows.
---`OPEN_NEW_WINDOW` opens a new window of the same application and moves it to the recorded place.
---`FORGET` opens no window, and the record drops out of the profile at the update after the switch,
---because an update records only the windows that exist.
local unmatched_window_action = enumeration.define({
    OPEN_NEW_WINDOW = "open_new_window",
    FORGET = "forget",
})

---@alias UnmatchedWindowAction "open_new_window"|"forget"

return unmatched_window_action
