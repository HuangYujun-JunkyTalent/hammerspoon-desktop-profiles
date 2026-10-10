local profile_state = require("desktop_manager.core.profile_state")

local state_file = {}

---@param path string
---@return string the path that the unreadable file was moved to
local function set_aside(path)
    local aside_path = string.format("%s.unreadable-%s", path, os.date("%Y%m%d-%H%M%S"))
    os.rename(path, aside_path)
    return aside_path
end

---Reads the saved state, or starts a new one when the file is missing.
---An unreadable file is moved aside, so that the next write does not destroy it.
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
    local aside_path = set_aside(path)
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
