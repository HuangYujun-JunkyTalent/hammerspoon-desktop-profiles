---The ways of taking the windows of the other profiles out of sight on a switch.
---`MINIMIZE_WINDOWS` minimizes each window, which puts it in the Dock.
---`HIDE_APPLICATIONS` hides an application whose windows all belong to other profiles, and
---minimizes the windows of the other profiles in any other application.
local concealment_method = {
    MINIMIZE_WINDOWS = "minimize_windows",
    HIDE_APPLICATIONS = "hide_applications",
}

local VALID = {
    [concealment_method.MINIMIZE_WINDOWS] = true,
    [concealment_method.HIDE_APPLICATIONS] = true,
}

---@param value any
---@return boolean
function concealment_method.is_valid(value)
    return VALID[value] == true
end

return concealment_method
