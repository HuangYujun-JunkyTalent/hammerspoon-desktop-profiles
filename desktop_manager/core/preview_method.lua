---What the list of numbered applications shows beside the title of a window.
---`APP_ICONS` shows the icon of the application.
---`BLURRED_SNAPSHOTS` shows a blurred image of the window, and the icon when no image comes.
---A snapshot needs the permission for Screen Recording, and on macOS 27.0.1 the function behind it
---once blocked Hammerspoon for two minutes, so icons are the default.
local preview_method = {
    APP_ICONS = "app_icons",
    BLURRED_SNAPSHOTS = "blurred_snapshots",
}

local VALID = {
    [preview_method.APP_ICONS] = true,
    [preview_method.BLURRED_SNAPSHOTS] = true,
}

---@param value any
---@return boolean
function preview_method.is_valid(value)
    return VALID[value] == true
end

return preview_method
