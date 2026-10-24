local enumeration = require("desktop_manager.core.enumeration")

---What a switch does for a recorded window whose window id no longer exists.
---`MATCH_TITLE` matches by the title in two ways.
---Under `match_windows_by.ID`, an open window of the same application with the same title takes
---the record.
---Under either way of matching windows, an unrecorded window of the same application with the same
---title counts as the reopened window, and takes the records of the closed window in every profile.
---Under `match_windows_by.ID`, `MATCH_ID_ALONE` matches a record by its window id alone, and under
---either way of matching windows it counts no window as reopened.
---`unmatched_window_action` alone decides whether a new window opens for a record that no open
---window matches, under either value.
---@class MissingWindowPolicyModule: Enumeration
---@field MATCH_ID_ALONE "match_id_alone"
---@field MATCH_TITLE "match_title"
---@field OPEN_NEW_WINDOW "open_new_window" the former name of `MATCH_ID_ALONE`
---@field MATCH_TITLE_OR_OPEN_NEW_WINDOW "match_title_or_open_new_window" the former name of
---`MATCH_TITLE`
local missing_window_policy = enumeration.define({
    MATCH_ID_ALONE = "match_id_alone",
    MATCH_TITLE = "match_title",
})

---@alias MissingWindowPolicy "match_id_alone"|"match_title"

---The former names of the values, which a copy of the settings from an earlier version may write.
---Each gives its former value, which `is_valid` refuses and `settings_check.replace_old_values`
---replaces.
missing_window_policy.OPEN_NEW_WINDOW = "open_new_window"
missing_window_policy.MATCH_TITLE_OR_OPEN_NEW_WINDOW = "match_title_or_open_new_window"

---The former values of the setting, which named a new window that `unmatched_window_action`
---decides, with the value that takes the place of each.
---@type table<string, MissingWindowPolicy>
missing_window_policy.OLD_VALUES = {
    [missing_window_policy.OPEN_NEW_WINDOW] = missing_window_policy.MATCH_ID_ALONE,
    [missing_window_policy.MATCH_TITLE_OR_OPEN_NEW_WINDOW] = missing_window_policy.MATCH_TITLE,
}

---@param policy string a value of missing_window_policy
---@return boolean
function missing_window_policy.matches_titles(policy)
    return policy == missing_window_policy.MATCH_TITLE
end

return missing_window_policy
