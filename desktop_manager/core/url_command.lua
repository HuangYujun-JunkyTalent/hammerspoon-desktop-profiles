---Commands carried by URLs such as `hammerspoon://desktop-manager?action=activate&profile=2`.
local url_command = {
    ACTIVATE = "activate",
    DEACTIVATE = "deactivate",
    TOGGLE = "toggle",
    RENAME = "rename",
    CYCLE_MONITOR_MATCHING = "cycle-monitor-matching",
    SAVE = "save",
    NUMBER_APP = "number-app",
    RELEASE_APP_NUMBER = "release-app-number",
    RESET_APP_NUMBERS = "reset-app-numbers",
    CLEAR = "clear",
    SEARCH_WINDOWS = "search-windows",
}

---@class Command
---@field action string a value of `url_command`
---@field profile_number integer|nil
---@field name string|nil
---@field app_number integer|nil
---@field app string|nil the name or the bundle id of a running application

---@class UrlLimits
---@field profile_count integer
---@field app_number_count integer

local ACTIONS_WITH_PROFILE = {
    [url_command.ACTIVATE] = true,
    [url_command.TOGGLE] = true,
    [url_command.RENAME] = true,
    [url_command.CLEAR] = true,
}

local ACTIONS_WITHOUT_PROFILE = {
    [url_command.CYCLE_MONITOR_MATCHING] = true,
    [url_command.SAVE] = true,
    [url_command.RESET_APP_NUMBERS] = true,
    [url_command.SEARCH_WINDOWS] = true,
}

---`deactivate` without a profile deactivates the active profile, and with a profile deactivates
---that profile when it is the active one.
local ACTIONS_WITH_OPTIONAL_PROFILE = {
    [url_command.DEACTIVATE] = true,
}

---@param text any
---@param what string the word for the number in a message, such as "profile"
---@param count integer
---@return integer|nil number
---@return string|nil error_message
local function parse_number(text, what, count)
    local number = math.tointeger(tonumber(text))
    if not number or number < 1 or number > count then
        return nil,
            string.format("the %s %q is not a number from 1 to %d", what, tostring(text), count)
    end
    return number, nil
end

---@param params table<string, string>
---@param limits UrlLimits
---@return Command|nil command
---@return string|nil error_message
local function parse_app_number_command(params, limits)
    local app_number, number_error =
        parse_number(params.number, "app number", limits.app_number_count)
    if not app_number then
        return nil, number_error
    end
    if params.action == url_command.RELEASE_APP_NUMBER then
        return { action = params.action, app_number = app_number }, nil
    end
    local app = (params.app or ""):match("^%s*(.-)%s*$")
    if app == "" then
        return nil, "the number-app action has no app parameter with a visible character"
    end
    return { action = params.action, app_number = app_number, app = app }, nil
end

---@param params table<string, string>
---@param limits UrlLimits
---@return Command|nil command
---@return string|nil error_message
function url_command.parse(params, limits)
    local action = params.action
    if action == nil then
        return nil, "the URL has no action parameter"
    end
    if action == url_command.NUMBER_APP or action == url_command.RELEASE_APP_NUMBER then
        return parse_app_number_command(params, limits)
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
    local profile_number, profile_error =
        parse_number(params.profile, "profile", limits.profile_count)
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
