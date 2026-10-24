local profile_state = require("desktop_manager.core.profile_state")

local state_file = {}

---@param path string
---@return string aside_path the path that the unreadable file goes to
---@return string|nil rename_error the error of the move, or nil once the file has moved
local function set_aside(path)
    local aside_path = string.format("%s.unreadable-%s", path, os.date("%Y%m%d-%H%M%S"))
    local is_moved, rename_error = os.rename(path, aside_path)
    if is_moved then
        return aside_path, nil
    end
    return aside_path, tostring(rename_error)
end

---Reads the saved state, or starts a new one when the file is missing.
---An unreadable file is moved aside, so that the next write does not destroy it.
---When the move fails, the warning says so, and the next write replaces the file.
---@param path string
---@param initial_monitor_matching string
---@return State state
---@return string|nil warning
function state_file.read(path, initial_monitor_matching)
    if not hs.fs.attributes(path) then
        return profile_state.new_state(initial_monitor_matching), nil
    end
    local state, error_message = profile_state.decode(hs.json.read(path))
    if state then
        return state, nil
    end
    local aside_path, rename_error = set_aside(path)
    if rename_error then
        return profile_state.new_state(initial_monitor_matching),
            string.format(
                "%s, and the move to %s failed with %q, so a new state started and the next save"
                    .. " replaces the file",
                error_message,
                aside_path,
                rename_error
            )
    end
    return profile_state.new_state(initial_monitor_matching),
        string.format(
            "%s, so it was moved to %s and a new state started",
            error_message,
            aside_path
        )
end

---@param path string
---@param state State
---@return boolean is_written
function state_file.write(path, state)
    return hs.json.write(state, path, true, true)
end

return state_file
