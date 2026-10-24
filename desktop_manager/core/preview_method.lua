local enumeration = require("desktop_manager.core.enumeration")

---What the list of numbered applications shows beside the title of a window.
---`APP_ICONS` shows the icon of the application.
---`BLURRED_SNAPSHOTS` shows a blurred image of the window, and the icon when no image comes.
---A slow snapshot turns the snapshots off until the next reload, because the function behind it
---can block Hammerspoon, as the README section "The previews of the list need the permission for
---Screen Recording" says.
local preview_method = enumeration.define({
    APP_ICONS = "app_icons",
    BLURRED_SNAPSHOTS = "blurred_snapshots",
})

---@alias PreviewMethod "app_icons"|"blurred_snapshots"

return preview_method
