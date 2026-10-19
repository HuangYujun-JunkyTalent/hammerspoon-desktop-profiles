local monitor_configuration = require("desktop_manager.core.monitor_configuration")

local missing_windows = {}

---A recorded window in sight whose window no longer exists, with the place of its new window.
---@class MissingWindow
---@field record WindowRecord
---@field placement WindowPlacement the window id of the placement is the id that no longer exists

---@class MissingWindowPlan
---@field missing_windows MissingWindow[] ordered by the screens of the configuration, then by
---desktop
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

---Orders the missing windows by the place of their new windows.
---A new window opens on the desktop that shows, and the restore moves it to its desktop by its
---frame and its id, so the order is the one in which the windows open.
---@param records WindowRecord[] records in sight whose windows no longer exist
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return MissingWindowPlan
function missing_windows.plan(records, configuration, desktop_layout)
    local planned, unplaced_records = {}, {}
    for _, record in ipairs(records) do
        local slot = record.slot_key
            and monitor_configuration.find_slot(configuration, record.slot_key)
        local desktop_count = slot and count_desktops(desktop_layout, slot.screen_uuid) or 0
        if not slot or not record.desktop_number or desktop_count == 0 then
            table.insert(unplaced_records, record)
        else
            table.insert(planned, {
                record = record,
                placement = {
                    window_id = record.window_id,
                    screen_uuid = slot.screen_uuid,
                    slot_key = slot.slot_key,
                    desktop_number = math.min(record.desktop_number, desktop_count),
                    unit_frame = record.unit_frame,
                },
            })
        end
    end
    local screen_order, record_order = {}, {}
    for index, slot in ipairs(configuration.slots) do
        screen_order[slot.screen_uuid] = index
    end
    for index, missing_window in ipairs(planned) do
        record_order[missing_window] = index
    end
    table.sort(planned, function(first, second)
        if first.placement.screen_uuid ~= second.placement.screen_uuid then
            return screen_order[first.placement.screen_uuid]
                < screen_order[second.placement.screen_uuid]
        end
        if first.placement.desktop_number ~= second.placement.desktop_number then
            return first.placement.desktop_number < second.placement.desktop_number
        end
        return record_order[first] < record_order[second]
    end)
    return { missing_windows = planned, unplaced_records = unplaced_records }
end

return missing_windows
