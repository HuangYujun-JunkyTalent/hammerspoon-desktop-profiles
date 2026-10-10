local deep_copy = {}

---@generic T
---@param value T
---@return T
function deep_copy.copy(value)
    if type(value) ~= "table" then
        return value
    end
    local copied = {}
    for key, nested_value in pairs(value) do
        copied[deep_copy.copy(key)] = deep_copy.copy(nested_value)
    end
    return copied
end

return deep_copy
