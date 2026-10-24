---The title that the list and the search show for a window.
local window_titles = {}

local UNTITLED = "untitled window"

---@param title string the title that macOS reports, empty without the permission for Screen
---Recording or for a window without a title
---@return string the title, or "untitled window" for an empty title
function window_titles.describe(title)
    return title ~= "" and title or UNTITLED
end

return window_titles
