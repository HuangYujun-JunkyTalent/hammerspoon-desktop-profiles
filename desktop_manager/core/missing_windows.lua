local locate_desktops = require("desktop_manager.core.locate_desktops")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local restore_plan = require("desktop_manager.core.restore_plan")

local missing_windows = {}

---The kinds of a record that no open window matched at a switch.
---`OUT_OF_SIGHT` is a record out of sight, which gets no new window.
---`ON_UNSEEN_DESKTOP` is a record whose window macOS lists on a desktop where Hammerspoon has not
---seen it, so the record keeps that window.
---`MISSING` is a record in sight whose window no longer exists.
missing_windows.UNMATCHED_KIND = {
    OUT_OF_SIGHT = "out_of_sight",
    ON_UNSEEN_DESKTOP = "on_unseen_desktop",
    MISSING = "missing",
}

---@alias UnmatchedKind "out_of_sight"|"on_unseen_desktop"|"missing"

---A record that no open window matched at a switch, with its kind.
---@class ClassifiedRecord
---@field record WindowRecord
---@field kind UnmatchedKind
---@field space_id integer|nil the desktop where macOS lists the window of an `ON_UNSEEN_DESKTOP`

---A recorded window in sight whose window no longer exists, with the place of its new window.
---@class MissingWindow
---@field record WindowRecord
---@field placement WindowPlacement the window id of the placement is the id that no longer exists

---@class MissingWindowPlan
---@field missing_windows MissingWindow[] ordered by the screens of the configuration, then by
---desktop
---@field unplaced_records WindowRecord[] records whose screen or desktop the configuration lacks

---Gives each record that no open window matched its kind, in the order of the records.
---@param records WindowRecord[]
---@param find_space_id fun(window_id: integer): integer|nil the desktop where macOS lists a window,
---which is read for every record with a window id
---@return ClassifiedRecord[]
function missing_windows.classify_unmatched(records, find_space_id)
    local classified = {}
    for _, record in ipairs(records) do
        local space_id = record.window_id and find_space_id(record.window_id)
        if record.is_out_of_sight then
            table.insert(
                classified,
                { record = record, kind = missing_windows.UNMATCHED_KIND.OUT_OF_SIGHT }
            )
        elseif space_id then
            table.insert(classified, {
                record = record,
                kind = missing_windows.UNMATCHED_KIND.ON_UNSEEN_DESKTOP,
                space_id = space_id,
            })
        else
            table.insert(
                classified,
                { record = record, kind = missing_windows.UNMATCHED_KIND.MISSING }
            )
        end
    end
    return classified
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
        local screen = slot and locate_desktops.find_screen(desktop_layout, slot.screen_uuid)
        local desktop_count = screen and #screen.space_ids or 0
        if not slot or not record.desktop_number or desktop_count == 0 then
            table.insert(unplaced_records, record)
        else
            table.insert(planned, {
                record = record,
                placement = restore_plan.place_record(
                    record,
                    slot,
                    desktop_count,
                    record.window_id
                ),
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
