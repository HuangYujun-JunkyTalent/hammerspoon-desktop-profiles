local enumeration = require("desktop_manager.core.enumeration")

---What a switch does for a recorded window whose window id no longer exists.
---`MATCH_TITLE_OR_OPEN_NEW_WINDOW` matches by the title in two ways.
---Under `match_windows_by.ID`, an open window of the same application with the same title takes
---the record.
---Under either way of matching windows, an unrecorded window of the same application with the same
---title counts as the reopened window, and takes the records of the closed window in every profile.
---Under `match_windows_by.ID`, `OPEN_NEW_WINDOW` matches a record by its window id alone, and under
---either way of matching windows it counts no window as reopened.
---`unmatched_window_action` alone decides whether a new window opens for a record that no open
---window matches, under either value.
---@class MissingWindowPolicyModule: Enumeration
---@field OPEN_NEW_WINDOW "open_new_window"
---@field MATCH_TITLE_OR_OPEN_NEW_WINDOW "match_title_or_open_new_window"
local missing_window_policy = enumeration.define({
    OPEN_NEW_WINDOW = "open_new_window",
    MATCH_TITLE_OR_OPEN_NEW_WINDOW = "match_title_or_open_new_window",
})

---@alias MissingWindowPolicy "open_new_window"|"match_title_or_open_new_window"

---@param policy string a value of missing_window_policy
---@return boolean
function missing_window_policy.matches_titles(policy)
    return policy == missing_window_policy.MATCH_TITLE_OR_OPEN_NEW_WINDOW
end

return missing_window_policy
