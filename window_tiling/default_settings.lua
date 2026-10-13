local default_settings = {}

---@class TilingSettings
---@field url_event_name string

---The shortcuts of the tiling are in the center of the keyboard shortcuts of every utility.
---@return TilingSettings
function default_settings.create()
    return {
        url_event_name = "window-tiling",
    }
end

return default_settings
