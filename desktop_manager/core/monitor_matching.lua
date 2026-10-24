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

---Raises an error when the matching names no way of deciding when two monitor configurations are
---the same, and the error names the place that called the function that runs the check.
---@param matching any
function monitor_matching.check(matching)
    if not monitor_matching.is_valid(matching) then
        error(string.format("unknown monitor matching %q", tostring(matching)), 3)
    end
end

---@return string[]
function monitor_matching.all()
    return { table.unpack(ORDER) }
end

---@param matching string
---@return string
function monitor_matching.label_of(matching)
    monitor_matching.check(matching)
    return LABELS[matching]
end

---@param matching string
---@return string
function monitor_matching.next_after(matching)
    monitor_matching.check(matching)
    local index = 1
    while ORDER[index] ~= matching do
        index = index + 1
    end
    return ORDER[index % #ORDER + 1]
end

return monitor_matching
