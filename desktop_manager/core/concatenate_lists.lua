local concatenate_lists = {}

---@generic T
---@param ... T[]
---@return T[] the items of the lists, list after list
function concatenate_lists.concatenate(...)
    local joined = {}
    for _, list in ipairs({ ... }) do
        for _, item in ipairs(list) do
            table.insert(joined, item)
        end
    end
    return joined
end

return concatenate_lists
