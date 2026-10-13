---What a switch tries first when it pairs a recorded window with an open window.
---`TITLE` takes the open window of the same application with the same title, the one with the
---recorded id first, and takes the window with the recorded id when no title matches, as for a
---browser window that shows another tab.
---`ID` takes the window with the recorded id, and takes a window with the same title when that
---window no longer exists, as `missing_window_policy` allows.
local match_windows_by = {
    TITLE = "title",
    ID = "id",
}

local VALID = {
    [match_windows_by.TITLE] = true,
    [match_windows_by.ID] = true,
}

---@param value any
---@return boolean
function match_windows_by.is_valid(value)
    return VALID[value] == true
end

return match_windows_by
