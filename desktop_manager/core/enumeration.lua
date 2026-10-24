---A closed set of strings, each value named by a constant, with the test of a value against it.
local enumeration = {}

---@class Enumeration
---@field is_valid fun(value: any): boolean true for the string values of the constants alone

---@generic T: table<string, string>
---@param constants T the name of each value, in capitals, with the value
---@return T|Enumeration enumeration the constants and `is_valid`
function enumeration.define(constants)
    local is_member = {}
    local defined = {}
    for name, value in pairs(constants) do
        is_member[value] = true
        defined[name] = value
    end
    function defined.is_valid(value)
        return is_member[value] == true
    end
    return defined
end

return enumeration
