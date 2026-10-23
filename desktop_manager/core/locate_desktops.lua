---Finds the screens, the desktops and the desktop that each screen shows in a layout of the
---desktops.
local locate_desktops = {}

---@class ScreenDesktops
---@field screen_uuid string
---@field screen_frame Rect
---@field space_ids integer[] the user desktops of the screen, in Mission Control order
---@field active_space_id integer|nil

---@class DesktopLayout
---@field screens ScreenDesktops[]
---@field focused_space_id integer|nil

---@class SpaceLocation
---@field screen ScreenDesktops
---@field desktop_number integer

---@param desktop_layout DesktopLayout
---@param space_id integer|nil
---@return SpaceLocation|nil
function locate_desktops.locate_space(desktop_layout, space_id)
    if space_id == nil then
        return nil
    end
    for _, screen in ipairs(desktop_layout.screens) do
        for desktop_number, candidate in ipairs(screen.space_ids) do
            if candidate == space_id then
                return { screen = screen, desktop_number = desktop_number }
            end
        end
    end
    return nil
end

---@param screen ScreenDesktops
---@return integer|nil the position of the desktop that the screen shows, nil for a space in full
---screen, which is no user desktop
function locate_desktops.find_shown_desktop_number(screen)
    for desktop_number, space_id in ipairs(screen.space_ids) do
        if space_id == screen.active_space_id then
            return desktop_number
        end
    end
    return nil
end

---@param desktop_layout DesktopLayout
---@param screen_uuid string
---@return ScreenDesktops|nil
function locate_desktops.find_screen(desktop_layout, screen_uuid)
    for _, screen in ipairs(desktop_layout.screens) do
        if screen.screen_uuid == screen_uuid then
            return screen
        end
    end
    return nil
end

return locate_desktops
