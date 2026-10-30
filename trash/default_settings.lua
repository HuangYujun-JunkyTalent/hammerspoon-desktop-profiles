local default_settings = {}

---@class TrashSettings
---@field url_event_name string

---@return TrashSettings
function default_settings.create()
    return {
        url_event_name = "trash",
    }
end

return default_settings
