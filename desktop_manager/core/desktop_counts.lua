local deep_copy = require("desktop_manager.core.deep_copy")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")

---Keeps the number of desktops of each display, so that the desktops that macOS moves to a display
---when another display disconnects can be told apart and removed once they are empty.
---macOS appends those desktops at the end of the display that stays, and removes none of them when
---the other display returns.
local desktop_counts = {}

---The desktops of each display at one reading.
---@class DesktopReading
---@field displays_key string the UUIDs of the displays that macOS reported, sorted, which changes
---whenever macOS moves desktops between displays
---@field counts table<string, integer> the number of desktops of each slot of the configuration

---@class DesktopCounts
---@field kept table<string, integer> the number of desktops of each display, by slot key
---@field last_reading DesktopReading|nil

---A desktop beyond the count of its display that the plan removes.
---@class DesktopRemoval
---@field screen_uuid string
---@field slot_key string
---@field space_ids integer[] from the end of the display
---@field staying_count integer the desktops beyond the count that stay, because they show or hold
---a window

---@return DesktopCounts
function desktop_counts.new()
    return { kept = {}, last_reading = nil }
end

---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return DesktopReading
function desktop_counts.read(configuration, desktop_layout)
    local uuids, counts = {}, {}
    for _, screen in ipairs(desktop_layout.screens) do
        table.insert(uuids, screen.screen_uuid)
        local slot = monitor_configuration.find_slot_of_screen(configuration, screen.screen_uuid)
        if slot then
            counts[slot.slot_key] = #screen.space_ids
        end
    end
    table.sort(uuids)
    return { displays_key = table.concat(uuids, ";"), counts = counts }
end

---Takes the user's changes of the desktops into the counts, and leaves out the moves of macOS.
---Between two readings of the same displays, a display that gains desktops keeps them all, and a
---display that loses desktops keeps at most the desktops it has left.
---Between readings of other displays, a count stays as it was, because macOS moved the desktops.
---A display without a count takes the desktops it has.
---@param counts DesktopCounts
---@param reading DesktopReading
---@return DesktopCounts
function desktop_counts.update(counts, reading)
    local kept = deep_copy.copy(counts.kept)
    local previous = counts.last_reading
    local previous_counts = previous
            and previous.displays_key == reading.displays_key
            and previous.counts
        or {}
    for slot_key, count in pairs(reading.counts) do
        local kept_count, previous_count = kept[slot_key], previous_counts[slot_key]
        if kept_count == nil then
            kept[slot_key] = count
        elseif previous_count and count > previous_count then
            kept[slot_key] = kept_count + count - previous_count
        elseif previous_count and count < previous_count then
            kept[slot_key] = math.min(kept_count, count)
        end
    end
    return { kept = kept, last_reading = deep_copy.copy(reading) }
end

---Limits the desktops that an arrangement adds to the counts, so that a restore after a change of
---monitors adds no desktop that the removal of the empty desktops would take away again.
---@param arrangement Arrangement
---@param counts DesktopCounts
---@return Arrangement
function desktop_counts.limit_arrangement(arrangement, counts)
    local limited = deep_copy.copy(arrangement)
    for _, monitor in ipairs(limited.monitors) do
        local kept_count = counts.kept[monitor.slot_key]
        if kept_count then
            monitor.desktop_count = math.min(monitor.desktop_count, kept_count)
        end
    end
    return limited
end

---Plans the removal of the desktops beyond the count of each display that do not show and hold no
---window, from the end of the display, where macOS appends the desktops it moves.
---@param counts DesktopCounts
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@param occupied_space_ids table<integer, boolean> the desktops that hold a window
---@return DesktopRemoval[] one per display with desktops beyond its count
function desktop_counts.plan_removals(counts, configuration, desktop_layout, occupied_space_ids)
    local removals = {}
    for _, screen in ipairs(desktop_layout.screens) do
        local slot = monitor_configuration.find_slot_of_screen(configuration, screen.screen_uuid)
        local kept_count = slot and counts.kept[slot.slot_key]
        if kept_count and #screen.space_ids > kept_count then
            local removal = {
                screen_uuid = screen.screen_uuid,
                slot_key = slot.slot_key,
                space_ids = {},
                staying_count = 0,
            }
            for position = #screen.space_ids, math.max(kept_count, 1) + 1, -1 do
                local space_id = screen.space_ids[position]
                if space_id == screen.active_space_id or occupied_space_ids[space_id] then
                    removal.staying_count = removal.staying_count + 1
                else
                    table.insert(removal.space_ids, space_id)
                end
            end
            table.insert(removals, removal)
        end
    end
    return removals
end

return desktop_counts
