local arrangement_capture = require("desktop_manager.core.arrangement_capture")

---Plans the way of one window to its placement without a switch of desktops.
---A window goes to another screen by its frame, which macOS 27.0.1 places on the desktop that shows
---there, and to another desktop of its screen by a move by its id.
---A frame is set only while the window is on a desktop in view, because a frame set out of view is
---untested, so a window out of view that needs a frame first comes into view by its id.
local window_routes = {}

---What the macOS layer reads of a window before it moves.
---@class WindowLocation
---@field space_ids integer[] the desktops that macOS lists for the window
---@field frame Rect|nil the frame, or nil when it cannot be read

---@class WindowRoute
---@field window_id integer
---@field view_space_id integer|nil the desktop in view of the screen that the window is on, where
---it goes first so that its frame is set in view
---@field target_frame Rect|nil the frame to set, nil when the frame stays
---@field target_space_id integer the desktop of the placement
---@field target_screen_uuid string
---@field is_across_screens boolean

window_routes.FRAME_TOLERANCE_POINTS = 2

---@param first Rect
---@param second Rect
---@return boolean whether two frames differ by at most the tolerance on every side
function window_routes.are_frames_close(first, second)
    local tolerance = window_routes.FRAME_TOLERANCE_POINTS
    return math.abs(first.x - second.x) <= tolerance
        and math.abs(first.y - second.y) <= tolerance
        and math.abs(first.w - second.w) <= tolerance
        and math.abs(first.h - second.h) <= tolerance
end

---@param desktop_layout DesktopLayout
---@param screen_uuid string
---@return ScreenDesktops|nil
local function find_screen(desktop_layout, screen_uuid)
    for _, screen in ipairs(desktop_layout.screens) do
        if screen.screen_uuid == screen_uuid then
            return screen
        end
    end
    return nil
end

---@param screen ScreenDesktops
---@return boolean whether the screen shows one of its desktops, and no space in full screen
local function shows_desktop(screen)
    for _, space_id in ipairs(screen.space_ids) do
        if space_id == screen.active_space_id then
            return true
        end
    end
    return false
end

---Plans the way of the window to its placement, in the order of the rules below.
---A placement whose desktop the layout lacks, a window on no desktop or on several, and a window in
---full screen stay.
---The recorded frame is set when it differs from the frame of the window, or when the frame of the
---window is unknown, and a placement without a recorded frame keeps the frame of the window.
---A window on another screen needs the recorded frame to go there, and stays without one.
---@param placement WindowPlacement
---@param location WindowLocation
---@param desktop_layout DesktopLayout
---@return WindowRoute|nil route nil when the window is on its desktop at its frame, or stays
---@return string|nil reason why the window stays, to follow the name of the window
function window_routes.plan(placement, location, desktop_layout)
    local target_screen = find_screen(desktop_layout, placement.screen_uuid)
    local target_space_id = target_screen and target_screen.space_ids[placement.desktop_number]
    if not target_screen or not target_space_id then
        return nil,
            string.format("has no desktop %d on %s", placement.desktop_number, placement.slot_key)
    end
    if #location.space_ids == 0 then
        return nil, "has no desktop now"
    end
    if #location.space_ids > 1 then
        return nil, "is on every desktop, and stays"
    end
    local space_id = location.space_ids[1]
    local location_in_layout = arrangement_capture.locate_space(desktop_layout, space_id)
    if not location_in_layout then
        return nil, "is in full screen, and stays"
    end
    local current_screen = location_in_layout.screen
    local recorded_frame = placement.unit_frame
        and arrangement_capture.from_unit_frame(placement.unit_frame, target_screen.screen_frame)
    local is_across_screens = current_screen.screen_uuid ~= target_screen.screen_uuid
    if is_across_screens and not recorded_frame then
        return nil, string.format("has no recorded frame for %s, and stays", placement.slot_key)
    end
    local target_frame = recorded_frame
    if
        target_frame
        and not is_across_screens
        and location.frame
        and window_routes.are_frames_close(location.frame, target_frame)
    then
        target_frame = nil
    end
    if not target_frame and space_id == target_space_id then
        return nil, nil
    end
    local view_space_id = nil
    if target_frame and space_id ~= current_screen.active_space_id then
        if not shows_desktop(current_screen) then
            return nil, "is out of view while its screen shows a window in full screen, and stays"
        end
        view_space_id = current_screen.active_space_id
    end
    if target_frame and is_across_screens and not shows_desktop(target_screen) then
        return nil,
            string.format("stays off %s, which shows a window in full screen", placement.slot_key)
    end
    return {
        window_id = placement.window_id,
        view_space_id = view_space_id,
        target_frame = target_frame,
        target_space_id = target_space_id,
        target_screen_uuid = target_screen.screen_uuid,
        is_across_screens = is_across_screens,
    },
        nil
end

return window_routes
