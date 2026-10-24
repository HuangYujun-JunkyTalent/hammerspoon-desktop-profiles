local monitor_matching = require("desktop_manager.core.monitor_matching")

local monitor_configuration = {}

---@class Rect
---@field x number
---@field y number
---@field w number
---@field h number

---@class ScreenDescription
---@field uuid string
---@field name string
---@field is_builtin boolean
---@field frame Rect

---A monitor slot is the role of one screen in a monitor configuration.
---Arrangements store desktops and windows per slot, so that the same slot finds its screen again.
---@class MonitorSlot
---@field slot_key string
---@field screen_uuid string

---@class MonitorConfiguration
---@field key string
---@field slots MonitorSlot[]

local BUILTIN_LABEL = "built-in"

---@param first ScreenDescription
---@param second ScreenDescription
---@return boolean
local function is_left_of(first, second)
    if first.frame.x ~= second.frame.x then
        return first.frame.x < second.frame.x
    end
    return first.frame.y < second.frame.y
end

---@param first ScreenDescription
---@param second ScreenDescription
---@return boolean
local function precedes_by_name(first, second)
    if first.name ~= second.name then
        return first.name < second.name
    end
    return is_left_of(first, second)
end

---@param screens ScreenDescription[]
---@param precedes fun(first: ScreenDescription, second: ScreenDescription): boolean
---@return ScreenDescription[]
local function sorted_copy(screens, precedes)
    local copied = { table.unpack(screens) }
    table.sort(copied, precedes)
    return copied
end

---Labels such as "LG TV" and "LG TV #2", where the number tells apart screens of the same label.
---@param labels string[]
---@return string[]
local function number_repeated_labels(labels)
    local seen_counts = {}
    local numbered = {}
    for _, label in ipairs(labels) do
        local count = (seen_counts[label] or 0) + 1
        seen_counts[label] = count
        table.insert(numbered, count == 1 and label or string.format("%s #%d", label, count))
    end
    return numbered
end

---@param screens ScreenDescription[]
---@param labels string[]
---@param key_parts string[]
---@return MonitorConfiguration
local function build_configuration(screens, labels, key_parts)
    local slots = {}
    for index, screen in ipairs(screens) do
        table.insert(slots, { slot_key = labels[index], screen_uuid = screen.uuid })
    end
    return { key = table.concat(key_parts, " + "), slots = slots }
end

---@param builtin_screens ScreenDescription[]
---@param external_screens ScreenDescription[]
---@return MonitorConfiguration
local function describe_by_count(builtin_screens, external_screens)
    local ordered = sorted_copy(builtin_screens, is_left_of)
    local labels = {}
    for _ in ipairs(ordered) do
        table.insert(labels, BUILTIN_LABEL)
    end
    for index, screen in ipairs(sorted_copy(external_screens, is_left_of)) do
        table.insert(ordered, screen)
        table.insert(labels, string.format("external %d", index))
    end
    local numbered_labels = number_repeated_labels(labels)
    local key_parts = {}
    if #builtin_screens > 0 then
        table.insert(
            key_parts,
            #builtin_screens == 1 and BUILTIN_LABEL
                or string.format("%d %s", #builtin_screens, BUILTIN_LABEL)
        )
    end
    if #external_screens > 0 then
        table.insert(key_parts, string.format("%d external", #external_screens))
    end
    return build_configuration(ordered, numbered_labels, key_parts)
end

---@param builtin_screens ScreenDescription[]
---@param external_screens ScreenDescription[]
---@return MonitorConfiguration
local function describe_by_identity(builtin_screens, external_screens)
    local ordered = sorted_copy(builtin_screens, is_left_of)
    local labels = {}
    for _ in ipairs(ordered) do
        table.insert(labels, BUILTIN_LABEL)
    end
    for _, screen in ipairs(sorted_copy(external_screens, precedes_by_name)) do
        table.insert(ordered, screen)
        table.insert(labels, screen.name)
    end
    local numbered_labels = number_repeated_labels(labels)
    return build_configuration(ordered, numbered_labels, numbered_labels)
end

---@param screens ScreenDescription[]
---@param matching string a value of `monitor_matching`
---@return MonitorConfiguration
function monitor_configuration.describe(screens, matching)
    if #screens == 0 then
        error("a monitor configuration needs at least one screen, and 0 were given", 2)
    end
    monitor_matching.check(matching)
    local builtin_screens, external_screens = {}, {}
    for _, screen in ipairs(screens) do
        table.insert(screen.is_builtin and builtin_screens or external_screens, screen)
    end
    if matching == monitor_matching.BY_COUNT then
        return describe_by_count(builtin_screens, external_screens)
    end
    return describe_by_identity(builtin_screens, external_screens)
end

---@param configuration MonitorConfiguration
---@param screen_uuid string
---@return MonitorSlot|nil
function monitor_configuration.find_slot_of_screen(configuration, screen_uuid)
    for _, slot in ipairs(configuration.slots) do
        if slot.screen_uuid == screen_uuid then
            return slot
        end
    end
    return nil
end

---@param configuration MonitorConfiguration
---@param slot_key string
---@return MonitorSlot|nil
function monitor_configuration.find_slot(configuration, slot_key)
    for _, slot in ipairs(configuration.slots) do
        if slot.slot_key == slot_key then
            return slot
        end
    end
    return nil
end

return monitor_configuration
