local monitor_configuration = require("desktop_manager.core.monitor_configuration")

local restore_plan = {}

---@class LiveWindowState
---@field bundle_id string
---@field space_id integer|nil
---@field is_minimized boolean
---@field is_app_hidden boolean

---@class DesktopCountChange
---@field screen_uuid string
---@field desktops_to_add integer
---@field space_ids_to_remove integer[] the last desktops of the screen, in Mission Control order

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
---@field desktop_count_changes DesktopCountChange[]
---@field placements_in_place WindowPlacement[] windows on their desktop, which need only a frame
---@field unminimizations_in_place WindowPlacement[] minimized windows that macOS keeps on their
---desktop, which need an unminimize and a frame
---@field visits DesktopVisit[] the desktops to switch to, with the windows to bring there
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

---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return DesktopCountChange[]
---@return table<string, integer> the desktop count that each screen will have
---@return table<string, boolean> the screens whose desktops change
local function plan_desktop_counts(arrangement, configuration, desktop_layout)
    local changes, target_counts, changed_screens = {}, {}, {}
    for _, monitor in ipairs(arrangement.monitors) do
        local slot = monitor_configuration.find_slot(configuration, monitor.slot_key)
        local screen = slot and find_screen(desktop_layout, slot.screen_uuid)
        if screen then
            local current_count = #screen.space_ids
            local target_count = math.max(monitor.desktop_count, 1)
            target_counts[screen.screen_uuid] = target_count
            if target_count ~= current_count then
                local space_ids_to_remove = {}
                for index = target_count + 1, current_count do
                    table.insert(space_ids_to_remove, screen.space_ids[index])
                end
                table.insert(changes, {
                    screen_uuid = screen.screen_uuid,
                    desktops_to_add = math.max(target_count - current_count, 0),
                    space_ids_to_remove = space_ids_to_remove,
                })
                changed_screens[screen.screen_uuid] = true
            end
        end
    end
    return changes, target_counts, changed_screens
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

---Plans the steps that bring the windows that the profile recorded in sight back to their saved
---desktops and frames.
---A window that the profile recorded out of sight is left to the concealment of the switch.
---The plan names desktops by their number on a screen, because adding desktops changes the ids.
---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@param matches WindowMatch[]
---@param live_states table<integer, LiveWindowState>
---@return RestorePlan
function restore_plan.plan(arrangement, configuration, desktop_layout, matches, live_states)
    local desktop_count_changes, target_counts, changed_screens =
        plan_desktop_counts(arrangement, configuration, desktop_layout)
    local plan = {
        bundle_ids_to_unhide = {},
        desktop_count_changes = desktop_count_changes,
        placements_in_place = {},
        unminimizations_in_place = {},
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
        local screen = slot and find_screen(desktop_layout, slot.screen_uuid)
        local is_on_target_desktop = state ~= nil
            and desktop_number ~= nil
            and screen ~= nil
            and not changed_screens[screen.screen_uuid]
            and screen.space_ids[desktop_number] == state.space_id
        if state and state.is_app_hidden and not record.is_out_of_sight then
            insert_once(plan.bundle_ids_to_unhide, state.bundle_id)
        end
        if not record.is_out_of_sight and slot and desktop_number then
            local placement = {
                window_id = match.window_id,
                screen_uuid = slot.screen_uuid,
                desktop_number = desktop_number,
                unit_frame = record.unit_frame,
            }
            if is_on_target_desktop and not state.is_minimized then
                table.insert(plan.placements_in_place, placement)
            elseif is_on_target_desktop then
                table.insert(plan.unminimizations_in_place, placement)
            else
                table.insert(visit_placements, placement)
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
