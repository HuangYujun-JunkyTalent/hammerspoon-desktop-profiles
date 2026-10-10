local read_screens = {}

---@param geometry table an hs.geometry rect
---@return Rect
function read_screens.to_rect(geometry)
    return { x = geometry.x, y = geometry.y, w = geometry.w, h = geometry.h }
end

---@param name string
---@param patterns string[]
---@return boolean
local function matches_any(name, patterns)
    for _, pattern in ipairs(patterns) do
        if name:find(pattern) then
            return true
        end
    end
    return false
end

---@param builtin_name_patterns string[] Lua patterns that the name of a built-in display matches
---@return ScreenDescription[]
function read_screens.describe_screens(builtin_name_patterns)
    local descriptions = {}
    for _, screen in ipairs(hs.screen.allScreens()) do
        local uuid = screen:getUUID()
        if uuid then
            local name = screen:name() or ""
            table.insert(descriptions, {
                uuid = uuid,
                name = name,
                is_builtin = matches_any(name, builtin_name_patterns),
                frame = read_screens.to_rect(screen:frame()),
            })
        end
    end
    return descriptions
end

---The UUID and the full frame of every screen.
---The signature changes when a monitor is connected, disconnected, arranged anew or set to another
---resolution, and stays when the Dock changes size.
---@return string
function read_screens.read_signature()
    local parts = {}
    for _, screen in ipairs(hs.screen.allScreens()) do
        local frame = screen:fullFrame()
        table.insert(
            parts,
            string.format(
                "%s@%g,%g,%g,%g",
                tostring(screen:getUUID()),
                frame.x,
                frame.y,
                frame.w,
                frame.h
            )
        )
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

---@param screen_uuid string
---@return table|nil screen an hs.screen
function read_screens.find_screen(screen_uuid)
    for _, screen in ipairs(hs.screen.allScreens()) do
        if screen:getUUID() == screen_uuid then
            return screen
        end
    end
    return nil
end

return read_screens
