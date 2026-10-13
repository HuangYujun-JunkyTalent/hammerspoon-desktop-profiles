local arrangement_capture = require("desktop_manager.core.arrangement_capture")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local switch_desktops = require("desktop_manager.macos.switch_desktops")

---Shows desktops and sets the frames of windows, for the restore and for the new windows.
local place_windows = {}

---@param screen_uuid string
---@return ScreenDesktops|nil
function place_windows.read_screen_desktops(screen_uuid)
    for _, screen in ipairs(read_desktops.read_desktop_layout().screens) do
        if screen.screen_uuid == screen_uuid then
            return screen
        end
    end
    return nil
end

local FRAME_TOLERANCE_POINTS = 2

---@param first Rect
---@param second Rect
---@return boolean
local function are_frames_close(first, second)
    return math.abs(first.x - second.x) <= FRAME_TOLERANCE_POINTS
        and math.abs(first.y - second.y) <= FRAME_TOLERANCE_POINTS
        and math.abs(first.w - second.w) <= FRAME_TOLERANCE_POINTS
        and math.abs(first.h - second.h) <= FRAME_TOLERANCE_POINTS
end

---Sets the saved frame of the window, unless the window already has it.
---@param window table an hs.window
---@param placement WindowPlacement
function place_windows.fit_frame(window, placement)
    local screen = read_screens.find_screen(placement.screen_uuid)
    if not screen or not placement.unit_frame then
        return
    end
    local target = arrangement_capture.from_unit_frame(
        placement.unit_frame,
        read_screens.to_rect(screen:frame())
    )
    if not target then
        return
    end
    if not are_frames_close(read_screens.to_rect(window:frame()), target) then
        window:setFrame(target, 0)
    end
end

---@param screen_uuid string
---@param desktop_number integer
---@param timing Timing
---@param on_done fun(space_id: integer|nil, error_message: string|nil)
function place_windows.show_desktop(screen_uuid, desktop_number, timing, on_done)
    local screen = place_windows.read_screen_desktops(screen_uuid)
    local space_ids = screen and screen.space_ids or {}
    local space_id = space_ids[math.min(desktop_number, #space_ids)]
    if not space_id then
        on_done(nil, string.format("screen %s has no desktops", screen_uuid))
        return
    end
    switch_desktops.switch_to_space(space_id, timing, function(error_message)
        on_done(space_id, error_message)
    end)
end

return place_windows
