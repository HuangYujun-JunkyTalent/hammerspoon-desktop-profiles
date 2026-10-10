local deep_copy = require("desktop_manager.core.deep_copy")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")

local arrangement_capture = {}

---What the tool reads of one window at the time of a capture.
---`space_id` and `frame` are nil when the tool could not read them, such as for a minimized window.
---A window is out of sight when it is minimized or its application is hidden.
---@class WindowObservation
---@field window_id integer
---@field bundle_id string
---@field app_name string
---@field title string
---@field space_id integer|nil
---@field frame Rect|nil
---@field is_out_of_sight boolean
---@field document string|nil

---@class ScreenDesktops
---@field screen_uuid string
---@field screen_frame Rect
---@field space_ids integer[] the user desktops of the screen, in Mission Control order
---@field active_space_id integer|nil

---@class DesktopLayout
---@field screens ScreenDesktops[]
---@field focused_space_id integer|nil

---@class MonitorDesktops
---@field slot_key string
---@field desktop_count integer

---@class DesktopLocation
---@field slot_key string
---@field desktop_number integer

---The desktops and windows that one profile recorded under one monitor configuration.
---@class Arrangement
---@field monitor_configuration_key string
---@field monitors MonitorDesktops[]
---@field focus DesktopLocation|nil
---@field windows WindowRecord[]

local UNIT_FRAME_DECIMALS = 10000

---@param value number
---@return number
local function round_unit(value)
    return math.floor(value * UNIT_FRAME_DECIMALS + 0.5) / UNIT_FRAME_DECIMALS
end

---@param frame Rect
---@param screen_frame Rect
---@return Rect
function arrangement_capture.to_unit_frame(frame, screen_frame)
    return {
        x = round_unit((frame.x - screen_frame.x) / screen_frame.w),
        y = round_unit((frame.y - screen_frame.y) / screen_frame.h),
        w = round_unit(frame.w / screen_frame.w),
        h = round_unit(frame.h / screen_frame.h),
    }
end

---@class SpaceLocation
---@field screen ScreenDesktops
---@field desktop_number integer

---@param desktop_layout DesktopLayout
---@param space_id integer|nil
---@return SpaceLocation|nil
function arrangement_capture.locate_space(desktop_layout, space_id)
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

---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@param space_id integer|nil
---@return DesktopLocation|nil
local function find_desktop_location(configuration, desktop_layout, space_id)
    local location = arrangement_capture.locate_space(desktop_layout, space_id)
    if not location then
        return nil
    end
    local slot =
        monitor_configuration.find_slot_of_screen(configuration, location.screen.screen_uuid)
    if not slot then
        return nil
    end
    return { slot_key = slot.slot_key, desktop_number = location.desktop_number }
end

---@param arrangement Arrangement|nil
---@return table<integer, WindowRecord>
local function index_records_by_window_id(arrangement)
    local records = {}
    for _, record in ipairs(arrangement and arrangement.windows or {}) do
        if record.window_id then
            records[record.window_id] = record
        end
    end
    return records
end

---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@param observation WindowObservation
---@param previous_record WindowRecord|nil
---@return WindowRecord
local function record_window(configuration, desktop_layout, observation, previous_record)
    local record = {
        window_id = observation.window_id,
        bundle_id = observation.bundle_id,
        app_name = observation.app_name,
        title = observation.title,
        is_out_of_sight = observation.is_out_of_sight,
        document = observation.document,
    }
    local location = arrangement_capture.locate_space(desktop_layout, observation.space_id)
    local slot = location
        and monitor_configuration.find_slot_of_screen(configuration, location.screen.screen_uuid)
    if location and slot then
        record.slot_key = slot.slot_key
        record.desktop_number = location.desktop_number
        if observation.frame then
            record.unit_frame =
                arrangement_capture.to_unit_frame(observation.frame, location.screen.screen_frame)
        end
    elseif previous_record then
        record.slot_key = previous_record.slot_key
        record.desktop_number = previous_record.desktop_number
    end
    if record.unit_frame == nil and previous_record then
        record.unit_frame = deep_copy.copy(previous_record.unit_frame)
    end
    return record
end

---Builds the arrangement of the observed windows.
---A window whose desktop or frame cannot be read keeps the location of its previous record.
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@param observations WindowObservation[]
---@param previous_arrangement Arrangement|nil
---@return Arrangement
function arrangement_capture.capture(
    configuration,
    desktop_layout,
    observations,
    previous_arrangement
)
    local monitors = {}
    for _, slot in ipairs(configuration.slots) do
        local desktop_count = 0
        for _, screen in ipairs(desktop_layout.screens) do
            if screen.screen_uuid == slot.screen_uuid then
                desktop_count = #screen.space_ids
            end
        end
        table.insert(monitors, { slot_key = slot.slot_key, desktop_count = desktop_count })
    end
    local previous_records = index_records_by_window_id(previous_arrangement)
    local windows = {}
    for _, observation in ipairs(observations) do
        local previous_record = previous_records[observation.window_id]
        table.insert(
            windows,
            record_window(configuration, desktop_layout, observation, previous_record)
        )
    end
    return {
        monitor_configuration_key = configuration.key,
        monitors = monitors,
        focus = find_desktop_location(
            configuration,
            desktop_layout,
            desktop_layout.focused_space_id
        ),
        windows = windows,
    }
end

return arrangement_capture
