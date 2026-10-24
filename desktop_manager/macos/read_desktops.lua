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

---@param layout DesktopLayout
---@return table<integer, string> the uuid of the screen of each desktop of the layout, by its space
function read_desktops.index_screen_of_each_space(layout)
    local screen_uuid_by_space = {}
    for _, screen in ipairs(layout.screens) do
        for _, space_id in ipairs(screen.space_ids) do
            screen_uuid_by_space[space_id] = screen.screen_uuid
        end
    end
    return screen_uuid_by_space
end

---@param window_id integer
---@return integer[] the desktops that macOS lists for the window, several for a window on all
---desktops
function read_desktops.list_window_space_ids(window_id)
    return hs.spaces.windowSpaces(window_id) or {}
end

---@param window_id integer
---@return integer|nil
function read_desktops.find_window_space_id(window_id)
    return read_desktops.list_window_space_ids(window_id)[1]
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

---@param screen_uuid string
---@return ScreenDesktops|nil
function read_desktops.find_screen_desktops(screen_uuid)
    for _, screen in ipairs(read_desktops.read_desktop_layout().screens) do
        if screen.screen_uuid == screen_uuid then
            return screen
        end
    end
    return nil
end

---@param space_id integer
---@return ScreenDesktops|nil the screen whose user desktops hold the desktop
function read_desktops.find_screen_of_space(space_id)
    for _, screen in ipairs(read_desktops.read_desktop_layout().screens) do
        for _, candidate in ipairs(screen.space_ids) do
            if candidate == space_id then
                return screen
            end
        end
    end
    return nil
end

---@param space_id integer
---@return string|nil the UUID of the screen whose spaces hold the space, a space in full screen
---included
function read_desktops.find_screen_uuid_of_any_space(space_id)
    for _, display in ipairs(read_managed_displays()) do
        for _, space in ipairs(display.Spaces or {}) do
            if space.ManagedSpaceID == space_id then
                return resolve_screen_uuid(display["Display Identifier"])
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
