local expect = {}

---@param value any
---@return string
local function describe(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    if type(value) ~= "table" then
        return tostring(value)
    end
    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys, function(first, second)
        return tostring(first) < tostring(second)
    end)
    local parts = {}
    for _, key in ipairs(keys) do
        table.insert(parts, string.format("[%s] = %s", describe(key), describe(value[key])))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

---@param first any
---@param second any
---@return boolean
local function are_equal(first, second)
    if type(first) ~= "table" or type(second) ~= "table" then
        return first == second
    end
    for key, value in pairs(first) do
        if not are_equal(value, second[key]) then
            return false
        end
    end
    for key in pairs(second) do
        if first[key] == nil then
            return false
        end
    end
    return true
end

---@param actual any
---@param expected any
function expect.equal(actual, expected)
    if not are_equal(actual, expected) then
        error(string.format("expected %s, got %s", describe(expected), describe(actual)), 2)
    end
end

---@param action fun()
---@param message_pattern string
function expect.raises(action, message_pattern)
    local is_successful, message = pcall(action)
    local expectation = string.format("expected an error matching %q", message_pattern)
    if is_successful then
        error(expectation .. ", and the call returned", 2)
    end
    if not tostring(message):find(message_pattern) then
        error(string.format("%s, got %q", expectation, tostring(message)), 2)
    end
end

return expect
