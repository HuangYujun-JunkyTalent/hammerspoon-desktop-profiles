---Commands carried by URLs such as `hammerspoon://desktop-manager?action=activate&profile=2`.
local url_command = {
    ACTIVATE = "activate",
    DEACTIVATE = "deactivate",
    TOGGLE = "toggle",
    RENAME = "rename",
    CYCLE_MONITOR_MATCHING = "cycle-monitor-matching",
    SAVE = "save",
}

---@class Command
---@field action string a value of `url_command`
---@field profile_number integer|nil
---@field name string|nil

local ACTIONS_WITH_PROFILE = {
    [url_command.ACTIVATE] = true,
    [url_command.TOGGLE] = true,
    [url_command.RENAME] = true,
}

local ACTIONS_WITHOUT_PROFILE = {
    [url_command.CYCLE_MONITOR_MATCHING] = true,
    [url_command.SAVE] = true,
}

---`deactivate` without a profile deactivates the active profile, and with a profile deactivates
---that profile when it is the active one.
local ACTIONS_WITH_OPTIONAL_PROFILE = {
    [url_command.DEACTIVATE] = true,
}

---@param text any
---@param profile_count integer
---@return integer|nil profile_number
---@return string|nil error_message
local function parse_profile_number(text, profile_count)
    local number = math.tointeger(tonumber(text))
    if not number or number < 1 or number > profile_count then
        return nil,
            string.format(
                "the profile %q is not a number from 1 to %d",
                tostring(text),
                profile_count
            )
    end
    return number, nil
end

---@param params table<string, string>
---@param profile_count integer
---@return Command|nil command
---@return string|nil error_message
function url_command.parse(params, profile_count)
    local action = params.action
    if action == nil then
        return nil, "the URL has no action parameter"
    end
    if ACTIONS_WITHOUT_PROFILE[action] then
        return { action = action }, nil
    end
    if ACTIONS_WITH_OPTIONAL_PROFILE[action] and params.profile == nil then
        return { action = action }, nil
    end
    if not ACTIONS_WITH_PROFILE[action] and not ACTIONS_WITH_OPTIONAL_PROFILE[action] then
        return nil, string.format("the action %q is unknown", action)
    end
    local profile_number, profile_error = parse_profile_number(params.profile, profile_count)
    if not profile_number then
        return nil, profile_error
    end
    if action ~= url_command.RENAME then
        return { action = action, profile_number = profile_number }, nil
    end
    local name = (params.name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        return nil, "the rename action has no name parameter with a visible character"
    end
    return { action = action, profile_number = profile_number, name = name }, nil
end

return url_command
