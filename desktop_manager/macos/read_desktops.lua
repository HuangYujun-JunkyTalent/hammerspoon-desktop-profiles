local read_screens = require("desktop_manager.macos.read_screens")

local read_desktops = {}

local USER_SPACE_TYPE = 0

---@return table[] the displays that macOS manages, each with its spaces in Mission Control order
local function read_managed_displays()
    local displays, error_message = hs.spaces.data_managedDisplaySpaces()
    if not displays then
        error("macOS did not report its desktops: " .. tostring(error_message), 2)
    end
    return displays
end

---macOS names the primary display "Main" when displays do not have separate Spaces.
---@param display_identifier string
---@return string
local function resolve_screen_uuid(display_identifier)
    if display_identifier == "Main" then
        return hs.screen.primaryScreen():getUUID()
    end
    return display_identifier
end

---@return DesktopLayout
function read_desktops.read_desktop_layout()
    local frames_by_uuid = {}
    for _, screen in ipairs(hs.screen.allScreens()) do
        local uuid = screen:getUUID()
        if uuid then
            frames_by_uuid[uuid] = read_screens.to_rect(screen:frame())
        end
    end
    local screens = {}
    for _, display in ipairs(read_managed_displays()) do
        local screen_uuid = resolve_screen_uuid(display["Display Identifier"])
        if frames_by_uuid[screen_uuid] then
            local space_ids = {}
            for _, space in ipairs(display.Spaces or {}) do
                if space.type == USER_SPACE_TYPE then
                    table.insert(space_ids, space.ManagedSpaceID)
                end
            end
            local current_space = display["Current Space"]
            table.insert(screens, {
                screen_uuid = screen_uuid,
                screen_frame = frames_by_uuid[screen_uuid],
                space_ids = space_ids,
                active_space_id = current_space and current_space.ManagedSpaceID or nil,
            })
        end
    end
    return { screens = screens, focused_space_id = hs.spaces.focusedSpace() }
end

---@param window_id integer
---@return integer|nil
function read_desktops.find_window_space_id(window_id)
    local space_ids = hs.spaces.windowSpaces(window_id)
    return space_ids and space_ids[1] or nil
end

---@param space_id integer
---@return boolean
function read_desktops.is_space_active(space_id)
    for _, screen in ipairs(read_desktops.read_desktop_layout().screens) do
        if screen.active_space_id == space_id then
            return true
        end
    end
    return false
end

---The number N of the macOS shortcut "Switch to Desktop N" that shows the desktop.
---Mission Control numbers the user desktops of all displays in one sequence.
---@param space_id integer
---@return integer|nil
function read_desktops.find_desktop_shortcut_number(space_id)
    local count = 0
    for _, display in ipairs(read_managed_displays()) do
        for _, space in ipairs(display.Spaces or {}) do
            if space.type == USER_SPACE_TYPE then
                count = count + 1
                if space.ManagedSpaceID == space_id then
                    return count
                end
            end
        end
    end
    return nil
end

---@param screen_uuid string
---@return integer[] every space of the screen, full-screen ones included, in Mission Control order
function read_desktops.list_all_space_ids_of_screen(screen_uuid)
    for _, display in ipairs(read_managed_displays()) do
        if resolve_screen_uuid(display["Display Identifier"]) == screen_uuid then
            local space_ids = {}
            for _, space in ipairs(display.Spaces or {}) do
                table.insert(space_ids, space.ManagedSpaceID)
            end
            return space_ids
        end
    end
    return {}
end

return read_desktops
