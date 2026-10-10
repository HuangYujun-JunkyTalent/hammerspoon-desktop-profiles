---The ways of deciding when two monitor configurations are the same.
---`BY_COUNT` compares the built-in display and the number of external monitors.
---`BY_IDENTITY` also compares the name of each external monitor.
local monitor_matching = {
    BY_COUNT = "by_count",
    BY_IDENTITY = "by_identity",
}

local ORDER = { monitor_matching.BY_COUNT, monitor_matching.BY_IDENTITY }

local LABELS = {
    [monitor_matching.BY_COUNT] = "Number of external monitors",
    [monitor_matching.BY_IDENTITY] = "Name of each external monitor",
}

---@param value any
---@return boolean
function monitor_matching.is_valid(value)
    return LABELS[value] ~= nil
end

---@return string[]
function monitor_matching.all()
    return { table.unpack(ORDER) }
end

---@param matching string
---@return string
function monitor_matching.label_of(matching)
    local label = LABELS[matching]
    if not label then
        error(string.format("unknown monitor matching %q", tostring(matching)), 2)
    end
    return label
end

---@param matching string
---@return string
function monitor_matching.next_after(matching)
    for index, candidate in ipairs(ORDER) do
        if candidate == matching then
            return ORDER[index % #ORDER + 1]
        end
    end
    error(string.format("unknown monitor matching %q", tostring(matching)), 2)
end

return monitor_matching
