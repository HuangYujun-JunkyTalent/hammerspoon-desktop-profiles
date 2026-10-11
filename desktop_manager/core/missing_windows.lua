local monitor_configuration = require("desktop_manager.core.monitor_configuration")

local missing_windows = {}

---A recorded window in sight whose window no longer exists, with the place of its new window.
---@class MissingWindow
---@field record WindowRecord
---@field placement WindowPlacement the window id of the placement is the id that no longer exists

---The desktop to show before the new windows open, because a new window opens on the desktop that
---shows and macOS 27.0.1 gives no way to move it to another desktop of its screen.
---@class MissingWindowVisit
---@field screen_uuid string
---@field desktop_number integer
---@field missing_windows MissingWindow[]

---@class MissingWindowPlan
---@field visits MissingWindowVisit[] ordered by the screens of the configuration, then by desktop
---@field unplaced_records WindowRecord[] records whose screen or desktop the configuration lacks

---@param desktop_layout DesktopLayout
---@param screen_uuid string
---@return integer the number of desktops of the screen, or 0 when the screen is absent
local function count_desktops(desktop_layout, screen_uuid)
    for _, screen in ipairs(desktop_layout.screens) do
        if screen.screen_uuid == screen_uuid then
            return #screen.space_ids
        end
    end
    return 0
end

---Groups the missing windows by the desktop where their new windows open.
---@param records WindowRecord[] records in sight whose windows no longer exist
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return MissingWindowPlan
function missing_windows.plan_visits(records, configuration, desktop_layout)
    local visits, unplaced_records = {}, {}
    for _, record in ipairs(records) do
        local slot = record.slot_key
            and monitor_configuration.find_slot(configuration, record.slot_key)
        local desktop_count = slot and count_desktops(desktop_layout, slot.screen_uuid) or 0
        if not slot or not record.desktop_number or desktop_count == 0 then
            table.insert(unplaced_records, record)
        else
            local desktop_number = math.min(record.desktop_number, desktop_count)
            local missing_window = {
                record = record,
                placement = {
                    window_id = record.window_id,
                    screen_uuid = slot.screen_uuid,
                    desktop_number = desktop_number,
                    unit_frame = record.unit_frame,
                },
            }
            local visit = nil
            for _, candidate in ipairs(visits) do
                if
                    candidate.screen_uuid == slot.screen_uuid
                    and candidate.desktop_number == desktop_number
                then
                    visit = candidate
                end
            end
            if visit then
                table.insert(visit.missing_windows, missing_window)
            else
                table.insert(visits, {
                    screen_uuid = slot.screen_uuid,
                    desktop_number = desktop_number,
                    missing_windows = { missing_window },
                })
            end
        end
    end
    local screen_order = {}
    for index, slot in ipairs(configuration.slots) do
        screen_order[slot.screen_uuid] = index
    end
    table.sort(visits, function(first, second)
        if first.screen_uuid ~= second.screen_uuid then
            return screen_order[first.screen_uuid] < screen_order[second.screen_uuid]
        end
        return first.desktop_number < second.desktop_number
    end)
    return { visits = visits, unplaced_records = unplaced_records }
end

return missing_windows
