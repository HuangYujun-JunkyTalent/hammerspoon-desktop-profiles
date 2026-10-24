local deep_copy = require("desktop_manager.core.deep_copy")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")

---Plans the removal of the desktops beyond the number that a profile holds on each display, and
---keeps the number of desktops of each display for a monitor configuration that the active profile
---has no layout for.
---macOS appends the desktops of a display that disconnects at the end of the display that stays,
---and removes none of them when the other display returns, so the kept numbers tell those desktops
---apart and the removal takes them away once they are empty.
local desktop_counts = {}

---The desktops of each display at one reading.
---@class DesktopReading
---@field displays_key string the UUIDs of the displays that macOS reported, sorted, which changes
---whenever macOS moves desktops between displays
---@field counts table<string, integer> the number of desktops of each slot of the configuration

---@class DesktopCounts
---@field kept table<string, integer> the number of desktops of each display, by slot key
---@field last_reading DesktopReading|nil

---The desktops beyond the count of a display that the plan removes.
---@class DesktopRemoval
---@field screen_uuid string
---@field slot_key string
---@field count integer the number of desktops that the display keeps
---@field space_ids integer[] from the end of the display
---@field staying_count integer the desktops beyond the count that stay
---@field empty_staying_space_ids integer[] the empty desktops that stay below a desktop that shows
---or holds a window, so that the desktops below them keep their numbers

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

---@param arrangement Arrangement
---@return table<string, integer> the number of desktops that the arrangement holds on each slot,
---at least 1
function desktop_counts.count_by_slot(arrangement)
    local counts = {}
    for _, monitor in ipairs(arrangement.monitors) do
        counts[monitor.slot_key] = math.max(monitor.desktop_count, 1)
    end
    return counts
end

---Plans the removal of the desktops beyond the count of each display that do not show and hold no
---window, from the end of the display, where macOS appends the desktops it moves.
---The removal of a display stops at the first desktop from the end that stays, so that a desktop
---that stays keeps its number, and the desktops below it keep theirs.
---@param count_by_slot table<string, integer> the number of desktops of each slot
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@param occupied_space_ids table<integer, boolean> the desktops that hold a window that keeps them
---@return DesktopRemoval[] one per display with desktops beyond its count
function desktop_counts.plan_removals(
    count_by_slot,
    configuration,
    desktop_layout,
    occupied_space_ids
)
    local removals = {}
    for _, screen in ipairs(desktop_layout.screens) do
        local slot = monitor_configuration.find_slot_of_screen(configuration, screen.screen_uuid)
        local count = slot and count_by_slot[slot.slot_key]
        if slot and count and #screen.space_ids > count then
            local removal = {
                screen_uuid = screen.screen_uuid,
                slot_key = slot.slot_key,
                count = count,
                space_ids = {},
                staying_count = 0,
                empty_staying_space_ids = {},
            }
            local has_stopped = false
            for position = #screen.space_ids, math.max(count, 1) + 1, -1 do
                local space_id = screen.space_ids[position]
                local is_kept = space_id == screen.active_space_id or occupied_space_ids[space_id]
                if is_kept or has_stopped then
                    removal.staying_count = removal.staying_count + 1
                    if not is_kept then
                        table.insert(removal.empty_staying_space_ids, space_id)
                    end
                    has_stopped = true
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
