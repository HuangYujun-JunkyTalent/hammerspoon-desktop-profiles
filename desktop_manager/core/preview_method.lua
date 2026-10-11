---What the list of numbered applications shows beside the title of a window.
---`APP_ICONS` shows the icon of the application.
---`BLURRED_SNAPSHOTS` shows a blurred image of the window, and the icon when no image comes.
---A snapshot needs the permission for Screen Recording.
---On macOS 27.0.1 the function behind it once blocked Hammerspoon for two minutes, before the
---user granted the permission, and afterwards it took less than 0.3 seconds.
---Snapshots are therefore the default, and a slow snapshot turns them off until the next reload.
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
