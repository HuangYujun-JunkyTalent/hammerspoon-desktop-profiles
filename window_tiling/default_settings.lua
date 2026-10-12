local tiling_position = require("window_tiling.core.tiling_position")

local default_settings = {}

---@class TilingSettings
---@field hotkey_modifiers string[] the modifiers that, with a key of `key_by_position`, tile the
---focused window. Control-Option with Return or an arrow are the default shortcuts of Rectangle.
---@field key_by_position table<string, string> the key of each value of tiling_position
---@field url_event_name string

---@return TilingSettings
function default_settings.create()
    return {
        hotkey_modifiers = { "ctrl", "alt" },
        key_by_position = {
            [tiling_position.FILL] = "return",
            [tiling_position.LEFT_HALF] = "left",
            [tiling_position.RIGHT_HALF] = "right",
            [tiling_position.TOP_HALF] = "up",
            [tiling_position.BOTTOM_HALF] = "down",
        },
        url_event_name = "window-tiling",
    }
end

return default_settings
