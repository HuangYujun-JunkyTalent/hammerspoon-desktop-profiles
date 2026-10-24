local deep_copy = require("desktop_manager.core.deep_copy")
local locate_desktops = require("desktop_manager.core.locate_desktops")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local unit_frames = require("desktop_manager.core.unit_frames")

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

---@class MonitorDesktops
---@field slot_key string
---@field desktop_count integer the number of desktops that the profile holds on the screen
---@field shown_desktop_number integer|nil the desktop that the screen showed, counted from 1

---The desktops and windows that one profile recorded under one monitor configuration.
---@class Arrangement
---@field monitor_configuration_key string
---@field monitors MonitorDesktops[]
---@field focused_slot_key string|nil the screen whose desktop had the focus
---@field windows WindowRecord[]

---@param arrangement Arrangement|nil
---@param slot_key string
---@return MonitorDesktops|nil
function arrangement_capture.find_monitor(arrangement, slot_key)
    for _, monitor in ipairs(arrangement and arrangement.monitors or {}) do
        if monitor.slot_key == slot_key then
            return monitor
        end
    end
    return nil
end

---An observation of a window that the window server lists and that Hammerspoon has not seen.
---@param window ServerWindow
---@param previous_record WindowRecord|nil
---@return WindowObservation
function arrangement_capture.observe_server_window(window, previous_record)
    return {
        window_id = window.window_id,
        bundle_id = window.bundle_id,
        app_name = window.app_name,
        title = (window.title == "" and previous_record) and previous_record.title or window.title,
        space_id = window.space_id,
        frame = window.frame,
        is_out_of_sight = false,
    }
end

---An observation of a recorded window that neither Hammerspoon nor the window server lists, and
---that sits on a desktop.
---@param record WindowRecord
---@param space_id integer the desktop that macOS lists for the window
---@return WindowObservation
function arrangement_capture.observe_unlisted_record(record, space_id)
    return {
        window_id = record.window_id,
        bundle_id = record.bundle_id,
        app_name = record.app_name,
        title = record.title,
        space_id = space_id,
        frame = nil,
        is_out_of_sight = record.is_out_of_sight,
    }
end

---@param screen ScreenDesktops
---@param space_id integer
---@return boolean whether the space is a desktop of the screen or the space that it shows
local function holds_space(screen, space_id)
    if screen.active_space_id == space_id then
        return true
    end
    for _, candidate in ipairs(screen.space_ids) do
        if candidate == space_id then
            return true
        end
    end
    return false
end

---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return string|nil the slot of the screen that holds the desktop with the focus
local function find_focused_slot_key(configuration, desktop_layout)
    local focused_space_id = desktop_layout.focused_space_id
    if focused_space_id == nil then
        return nil
    end
    for _, screen in ipairs(desktop_layout.screens) do
        if holds_space(screen, focused_space_id) then
            local slot =
                monitor_configuration.find_slot_of_screen(configuration, screen.screen_uuid)
            return slot and slot.slot_key
        end
    end
    return nil
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
    }
    local location = locate_desktops.locate_space(desktop_layout, observation.space_id)
    local slot = location
        and monitor_configuration.find_slot_of_screen(configuration, location.screen.screen_uuid)
    if location and slot then
        record.slot_key = slot.slot_key
        record.desktop_number = location.desktop_number
        if observation.frame and unit_frames.has_area(observation.frame) then
            record.unit_frame =
                unit_frames.to_unit_frame(observation.frame, location.screen.screen_frame)
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
---A frame without area counts as unread.
---A screen that shows a space in full screen keeps the shown desktop of its previous record, and so
---does the focus on a screen of no slot.
---A screen whose desktops macOS does not list keeps the record of its previous arrangement, and has
---no record without one, because a number of 0 would remove its desktops at the next restore.
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
        local screen = locate_desktops.find_screen(desktop_layout, slot.screen_uuid)
        local previous_monitor =
            arrangement_capture.find_monitor(previous_arrangement, slot.slot_key)
        if screen then
            table.insert(monitors, {
                slot_key = slot.slot_key,
                desktop_count = #screen.space_ids,
                shown_desktop_number = locate_desktops.find_shown_desktop_number(screen)
                    or previous_monitor and previous_monitor.shown_desktop_number
                    or nil,
            })
        elseif previous_monitor then
            table.insert(monitors, deep_copy.copy(previous_monitor))
        end
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
        focused_slot_key = find_focused_slot_key(configuration, desktop_layout)
            or previous_arrangement and previous_arrangement.focused_slot_key
            or nil,
        windows = windows,
    }
end

return arrangement_capture
