local enumeration = require("desktop_manager.core.enumeration")

---How the list of numbered applications chooses its sizes on the screen in front.
---`FILL_SCREEN` grows or shrinks the previews and the fonts until the list fills the screen.
---`FIXED` keeps the sizes of the settings, and shrinks them only to fit within the screen.
local list_sizing = enumeration.define({
    FILL_SCREEN = "fill_screen",
    FIXED = "fixed",
})

---@alias ListSizing "fill_screen"|"fixed"

return list_sizing
