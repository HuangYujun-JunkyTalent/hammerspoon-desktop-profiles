local arrangement_capture = require("desktop_manager.core.arrangement_capture")
local desktop_counts = require("desktop_manager.core.desktop_counts")
local locate_desktops = require("desktop_manager.core.locate_desktops")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")

local restore_plan = {}

---@class DesktopAddition
---@field screen_uuid string
---@field slot_key string
---@field desktops_to_add integer

---A window to bring to a desktop and to fit to its saved frame on that desktop's screen.
---@class WindowPlacement
---@field window_id integer
---@field screen_uuid string
---@field slot_key string the name of the screen in the messages, such as "built-in"
---@field desktop_number integer
---@field unit_frame Rect|nil

---The placement of the window of a record on its recorded desktop of the screen of the slot, or
---on the last desktop of that screen when the screen has fewer desktops.
---@param record WindowRecord a record with a desktop number
---@param slot MonitorSlot
---@param desktop_count integer the desktops that the screen has, or has once the restore adds them
---@param window_id integer
---@return WindowPlacement
function restore_plan.place_record(record, slot, desktop_count, window_id)
    return {
        window_id = window_id,
        screen_uuid = slot.screen_uuid,
        slot_key = slot.slot_key,
        desktop_number = math.min(record.desktop_number, desktop_count),
        unit_frame = record.unit_frame,
    }
end

---@class ScreenDesktop
---@field screen_uuid string
---@field slot_key string
---@field desktop_number integer

---@class RestorePlan
---@field bundle_ids_to_unhide string[]
---@field desktop_additions DesktopAddition[]
---@field unminimizations WindowPlacement[] the minimized windows that the profile recorded in sight
---@field placements WindowPlacement[] every window that the profile recorded in sight, the
---minimized ones included, in the order of the matches
---@field shown_desktops ScreenDesktop[] the desktops to show at the end, in the order of the slots,
---the slot of the focus last

---Plans the desktops to add at the end of each screen, up to the number that the arrangement
---holds, so the desktops that exist keep their numbers.
---The desktops beyond the number go after the windows are in place, as the controller does.
---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return DesktopAddition[]
---@return table<string, integer> the desktop count that each screen will have
local function plan_desktop_additions(arrangement, configuration, desktop_layout)
    local additions, target_counts = {}, {}
    local recorded_counts = desktop_counts.count_by_slot(arrangement)
    for _, monitor in ipairs(arrangement.monitors) do
        local slot = monitor_configuration.find_slot(configuration, monitor.slot_key)
        local screen = slot and locate_desktops.find_screen(desktop_layout, slot.screen_uuid)
        if screen then
            local current_count = #screen.space_ids
            local recorded_count = recorded_counts[monitor.slot_key]
            target_counts[screen.screen_uuid] = math.max(recorded_count, current_count)
            if recorded_count > current_count then
                table.insert(additions, {
                    screen_uuid = screen.screen_uuid,
                    slot_key = monitor.slot_key,
                    desktops_to_add = recorded_count - current_count,
                })
            end
        end
    end
    return additions, target_counts
end

---The desktop to show on each screen at the end of a restore, within the number of desktops that
---the arrangement holds there.
---A screen without a recorded shown desktop that shows a desktop beyond the number gets the last
---desktop within the number, so that the desktop it shows can go.
---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return ScreenDesktop[] in the order of the slots, the slot of the focus last
function restore_plan.plan_shown_desktops(arrangement, configuration, desktop_layout)
    local shown_desktops, desktop_of_focus = {}, nil
    local recorded_counts = desktop_counts.count_by_slot(arrangement)
    for _, slot in ipairs(configuration.slots) do
        local monitor = arrangement_capture.find_monitor(arrangement, slot.slot_key)
        local screen = locate_desktops.find_screen(desktop_layout, slot.screen_uuid)
        local count = recorded_counts[slot.slot_key]
        local desktop_number = monitor and monitor.shown_desktop_number
        local shown_position = screen and locate_desktops.find_shown_desktop_number(screen)
        if count and not desktop_number and shown_position and shown_position > count then
            desktop_number = count
        end
        if screen and desktop_number then
            local desktop = {
                screen_uuid = slot.screen_uuid,
                slot_key = slot.slot_key,
                desktop_number = math.min(desktop_number, count),
            }
            if slot.slot_key == arrangement.focused_slot_key then
                desktop_of_focus = desktop
            else
                table.insert(shown_desktops, desktop)
            end
        end
    end
    if desktop_of_focus then
        table.insert(shown_desktops, desktop_of_focus)
    end
    return shown_desktops
end

---The desktop to show first on each screen that shows a space in full screen, because a window
---moved there would join the window in full screen: the shown desktop that the arrangement records,
---or desktop 1.
---@param arrangement Arrangement|nil
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return ScreenDesktop[]
function restore_plan.plan_exits_from_full_screen(arrangement, configuration, desktop_layout)
    local exits = {}
    for _, slot in ipairs(configuration.slots) do
        local screen = locate_desktops.find_screen(desktop_layout, slot.screen_uuid)
        if
            screen
            and #screen.space_ids > 0
            and not locate_desktops.find_shown_desktop_number(screen)
        then
            local monitor = arrangement
                and arrangement_capture.find_monitor(arrangement, slot.slot_key)
            local desktop_number = monitor and monitor.shown_desktop_number or 1
            table.insert(exits, {
                screen_uuid = slot.screen_uuid,
                slot_key = slot.slot_key,
                desktop_number = math.min(desktop_number, #screen.space_ids),
            })
        end
    end
    return exits
end

---@param bundle_ids string[]
---@param bundle_id string
local function insert_once(bundle_ids, bundle_id)
    for _, existing in ipairs(bundle_ids) do
        if existing == bundle_id then
            return
        end
    end
    table.insert(bundle_ids, bundle_id)
end

---Plans the restore of the windows that the profile recorded in sight to their saved desktops and
---frames, and the desktops to add and to show.
---A window that the profile recorded out of sight is left to the concealment of the switch.
---The way of each window to its placement is planned after the desktops are added and the windows
---unminimized, as `window_routes` does.
---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@param matches WindowMatch[]
---@param window_states table<integer, WindowState> the state of each matched window
---@return RestorePlan
function restore_plan.plan(arrangement, configuration, desktop_layout, matches, window_states)
    local desktop_additions, target_counts =
        plan_desktop_additions(arrangement, configuration, desktop_layout)
    local plan = {
        bundle_ids_to_unhide = {},
        desktop_additions = desktop_additions,
        unminimizations = {},
        placements = {},
        shown_desktops = restore_plan.plan_shown_desktops(
            arrangement,
            configuration,
            desktop_layout
        ),
    }
    for _, match in ipairs(matches) do
        local record, state = match.record, window_states[match.window_id]
        local slot = record.slot_key
            and monitor_configuration.find_slot(configuration, record.slot_key)
        local target_count = slot and target_counts[slot.screen_uuid]
        if state and state.is_app_hidden and not record.is_out_of_sight then
            insert_once(plan.bundle_ids_to_unhide, state.bundle_id)
        end
        if
            state
            and not record.is_out_of_sight
            and slot
            and target_count
            and record.desktop_number
        then
            local placement = restore_plan.place_record(record, slot, target_count, match.window_id)
            table.insert(plan.placements, placement)
            if state.is_minimized then
                table.insert(plan.unminimizations, placement)
            end
        end
    end
    return plan
end

return restore_plan
