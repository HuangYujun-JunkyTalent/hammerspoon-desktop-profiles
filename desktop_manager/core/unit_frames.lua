---The frame of a window as fractions of the frame of its screen, which a record keeps, and the
---frame on a screen of such a unit frame.
local unit_frames = {}

local UNIT_FRAME_DECIMALS = 10000

---@param value number
---@return number
local function round_unit(value)
    return math.floor(value * UNIT_FRAME_DECIMALS + 0.5) / UNIT_FRAME_DECIMALS
end

---@param frame Rect
---@param screen_frame Rect
---@return Rect
function unit_frames.to_unit_frame(frame, screen_frame)
    return {
        x = round_unit((frame.x - screen_frame.x) / screen_frame.w),
        y = round_unit((frame.y - screen_frame.y) / screen_frame.h),
        w = round_unit(frame.w / screen_frame.w),
        h = round_unit(frame.h / screen_frame.h),
    }
end

---macOS reports a frame without area for some windows, and no window can be given one.
---@param frame Rect
---@return boolean
function unit_frames.has_area(frame)
    return frame.w > 0 and frame.h > 0
end

---The frame on the screen of a unit frame.
---A unit frame reaches past 0 or 1 for a window that reaches past the screen without the menu bar
---and the Dock, and `hs.geometry` refuses such a unit frame, so the conversion is done here.
---@param unit_frame Rect
---@param screen_frame Rect
---@return Rect|nil frame nil for a unit frame without area
function unit_frames.from_unit_frame(unit_frame, screen_frame)
    if not unit_frames.has_area(unit_frame) then
        return nil
    end
    return {
        x = math.floor(screen_frame.x + unit_frame.x * screen_frame.w),
        y = math.floor(screen_frame.y + unit_frame.y * screen_frame.h),
        w = math.floor(unit_frame.w * screen_frame.w),
        h = math.floor(unit_frame.h * screen_frame.h),
    }
end

return unit_frames
