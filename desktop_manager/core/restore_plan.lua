local monitor_configuration = require("desktop_manager.core.monitor_configuration")

local restore_plan = {}

---@class LiveWindowState
---@field bundle_id string
---@field space_id integer|nil
---@field is_minimized boolean
---@field is_app_hidden boolean

---@class DesktopAddition
---@field screen_uuid string
---@field desktops_to_add integer

---A window to bring to a desktop and to fit to its saved frame on that desktop's screen.
---@class WindowPlacement
---@field window_id integer
---@field screen_uuid string
---@field desktop_number integer
---@field unit_frame Rect|nil

---@class DesktopVisit
---@field screen_uuid string
---@field desktop_number integer
---@field placements WindowPlacement[]

---@class ScreenDesktop
---@field screen_uuid string
---@field desktop_number integer

---@class RestorePlan
---@field bundle_ids_to_unhide string[]
---@field desktop_additions DesktopAddition[]
---@field placements_in_place WindowPlacement[] windows on their desktop, which need only a frame
---@field unminimizations_in_place WindowPlacement[] minimized windows on the screen of their
---desktop, which macOS unminimizes onto the desktop they were minimized on
---@field window_ids_off_desktop integer[] windows in sight on another desktop of their screen,
---which macOS 27.0.1 gives no way to move
---@field visits DesktopVisit[] the desktops to show on other screens, with the windows to move
---@field focus ScreenDesktop|nil

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

---Plans the desktops to add, and no desktop to remove, because removing a desktop moves its
---windows to another desktop and changes what the other profiles recorded.
---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return DesktopAddition[]
---@return table<string, integer> the desktop count that each screen will have
local function plan_desktop_additions(arrangement, configuration, desktop_layout)
    local additions, target_counts = {}, {}
    for _, monitor in ipairs(arrangement.monitors) do
        local slot = monitor_configuration.find_slot(configuration, monitor.slot_key)
        local screen = slot and find_screen(desktop_layout, slot.screen_uuid)
        if screen then
            local current_count = #screen.space_ids
            local recorded_count = math.max(monitor.desktop_count, 1)
            target_counts[screen.screen_uuid] = math.max(recorded_count, current_count)
            if recorded_count > current_count then
                table.insert(additions, {
                    screen_uuid = screen.screen_uuid,
                    desktops_to_add = recorded_count - current_count,
                })
            end
        end
    end
    return additions, target_counts
end

---@param desktop_layout DesktopLayout
---@param space_id integer|nil
---@return string|nil the screen that holds the desktop
local function find_screen_of_space(desktop_layout, space_id)
    for _, screen in ipairs(desktop_layout.screens) do
        for _, candidate in ipairs(screen.space_ids) do
            if candidate == space_id then
                return screen.screen_uuid
            end
        end
    end
    return nil
end

---Groups the placements by the desktop they go to, in the order of their first placement.
---@param placements WindowPlacement[]
---@return DesktopVisit[]
function restore_plan.group_into_visits(placements)
    local visits = {}
    for _, placement in ipairs(placements) do
        local visit = nil
        for _, candidate in ipairs(visits) do
            if
                candidate.screen_uuid == placement.screen_uuid
                and candidate.desktop_number == placement.desktop_number
            then
                visit = candidate
            end
        end
        if visit then
            table.insert(visit.placements, placement)
        else
            table.insert(visits, {
                screen_uuid = placement.screen_uuid,
                desktop_number = placement.desktop_number,
                placements = { placement },
            })
        end
    end
    return visits
end

---@param configuration MonitorConfiguration
---@return table<string, integer> the position of each screen in the configuration
local function index_screen_order(configuration)
    local order = {}
    for index, slot in ipairs(configuration.slots) do
        order[slot.screen_uuid] = index
    end
    return order
end

---@param visits DesktopVisit[]
---@param configuration MonitorConfiguration
local function sort_visits(visits, configuration)
    local screen_order = index_screen_order(configuration)
    table.sort(visits, function(first, second)
        if first.screen_uuid ~= second.screen_uuid then
            return (screen_order[first.screen_uuid] or 0) < (screen_order[second.screen_uuid] or 0)
        end
        return first.desktop_number < second.desktop_number
    end)
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

---Plans the least work that brings the windows that the profile recorded in sight back to their
---saved desktops and frames.
---A window that the profile recorded out of sight is left to the concealment of the switch.
---Desktops are added at the end of a screen, so the desktops that exist keep their numbers.
---A window changes desktop only by moving to another screen, because macOS 27.0.1 unminimizes a
---window onto the desktop it was minimized on and Hammerspoon cannot move it between desktops.
---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@param matches WindowMatch[]
---@param live_states table<integer, LiveWindowState>
---@return RestorePlan
function restore_plan.plan(arrangement, configuration, desktop_layout, matches, live_states)
    local desktop_additions, target_counts =
        plan_desktop_additions(arrangement, configuration, desktop_layout)
    local plan = {
        bundle_ids_to_unhide = {},
        desktop_additions = desktop_additions,
        placements_in_place = {},
        unminimizations_in_place = {},
        window_ids_off_desktop = {},
        visits = {},
        focus = nil,
    }
    local visit_placements = {}
    for _, match in ipairs(matches) do
        local record, state = match.record, live_states[match.window_id]
        local slot = record.slot_key
            and monitor_configuration.find_slot(configuration, record.slot_key)
        local target_count = slot and target_counts[slot.screen_uuid]
        local desktop_number = target_count
            and record.desktop_number
            and math.min(record.desktop_number, target_count)
        if state and state.is_app_hidden and not record.is_out_of_sight then
            insert_once(plan.bundle_ids_to_unhide, state.bundle_id)
        end
        if state and not record.is_out_of_sight and slot and desktop_number then
            local placement = {
                window_id = match.window_id,
                screen_uuid = slot.screen_uuid,
                desktop_number = desktop_number,
                unit_frame = record.unit_frame,
            }
            local target_screen = find_screen(desktop_layout, slot.screen_uuid)
            local target_space_id = target_screen and target_screen.space_ids[desktop_number]
            local current_screen_uuid = find_screen_of_space(desktop_layout, state.space_id)
            local is_on_target_desktop = state.space_id ~= nil and state.space_id == target_space_id
            local is_on_target_screen = current_screen_uuid == slot.screen_uuid
            if is_on_target_desktop and not state.is_minimized then
                table.insert(plan.placements_in_place, placement)
            elseif state.is_minimized and (is_on_target_screen or current_screen_uuid == nil) then
                table.insert(plan.unminimizations_in_place, placement)
            elseif current_screen_uuid ~= nil and not is_on_target_screen then
                table.insert(visit_placements, placement)
            else
                table.insert(plan.window_ids_off_desktop, match.window_id)
            end
        end
    end
    plan.visits = restore_plan.group_into_visits(visit_placements)
    sort_visits(plan.visits, configuration)
    local focus_slot = arrangement.focus
        and monitor_configuration.find_slot(configuration, arrangement.focus.slot_key)
    if focus_slot and target_counts[focus_slot.screen_uuid] then
        plan.focus = {
            screen_uuid = focus_slot.screen_uuid,
            desktop_number = math.min(
                arrangement.focus.desktop_number,
                target_counts[focus_slot.screen_uuid]
            ),
        }
    end
    return plan
end

return restore_plan
