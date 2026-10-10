local deep_copy = require("desktop_manager.core.deep_copy")
local monitor_matching = require("desktop_manager.core.monitor_matching")

local profile_state = {}

---@class Profile
---@field number integer
---@field name string
---@field window_ids integer[] the open windows that belong to the profile, which may belong to
---other profiles as well
---@field arrangements table<string, Arrangement> keyed by monitor configuration key

---The state that the tool keeps between runs of Hammerspoon.
---Profiles are keyed by their number written as a string, because JSON objects have string keys.
---@class State
---@field format_version integer
---@field monitor_matching string
---@field active_profile_number integer|nil
---@field profiles table<string, Profile>

profile_state.FORMAT_VERSION = 1

---@param number any
local function check_profile_number(number)
    if math.type(number) ~= "integer" or number < 1 then
        error(
            string.format(
                "a profile number is a positive integer, and %s was given",
                tostring(number)
            ),
            3
        )
    end
end

---@param number integer
---@return string
local function key_of(number)
    return tostring(number)
end

---@param number integer
---@return Profile
local function new_profile(number)
    return {
        number = number,
        name = string.format("Profile %d", number),
        window_ids = {},
        arrangements = {},
    }
end

---@param matching string
---@return State
function profile_state.new_state(matching)
    if not monitor_matching.is_valid(matching) then
        error(string.format("unknown monitor matching %q", tostring(matching)), 2)
    end
    return {
        format_version = profile_state.FORMAT_VERSION,
        monitor_matching = matching,
        active_profile_number = nil,
        profiles = {},
    }
end

---@param state State
---@param number integer
---@return Profile
function profile_state.profile_or_default(state, number)
    check_profile_number(number)
    local profile = state.profiles[key_of(number)]
    return profile and deep_copy.copy(profile) or new_profile(number)
end

---@param state State
---@param profile Profile
---@return State
function profile_state.with_profile(state, profile)
    check_profile_number(profile.number)
    local updated = deep_copy.copy(state)
    updated.profiles[key_of(profile.number)] = deep_copy.copy(profile)
    return updated
end

---@param state State
---@param number integer|nil
---@return State
function profile_state.with_active_profile_number(state, number)
    if number ~= nil then
        check_profile_number(number)
    end
    local updated = deep_copy.copy(state)
    updated.active_profile_number = number
    return updated
end

---@param state State
---@param matching string
---@return State
function profile_state.with_monitor_matching(state, matching)
    if not monitor_matching.is_valid(matching) then
        error(string.format("unknown monitor matching %q", tostring(matching)), 2)
    end
    local updated = deep_copy.copy(state)
    updated.monitor_matching = matching
    return updated
end

---@param state State
---@param number integer
---@param name string
---@return State
function profile_state.rename_profile(state, number, name)
    local trimmed = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        error(
            string.format(
                "a profile name needs a visible character, and %q was given",
                tostring(name)
            ),
            2
        )
    end
    local profile = profile_state.profile_or_default(state, number)
    profile.name = trimmed
    return profile_state.with_profile(state, profile)
end

---@param window_ids integer[]
---@return table<integer, boolean>
local function to_set(window_ids)
    local set = {}
    for _, window_id in ipairs(window_ids) do
        set[window_id] = true
    end
    return set
end

---@param window_ids integer[]
---@param removed table<integer, boolean>
---@return integer[]
local function without(window_ids, removed)
    local kept = {}
    for _, window_id in ipairs(window_ids) do
        if not removed[window_id] then
            table.insert(kept, window_id)
        end
    end
    return kept
end

---@param state State
---@param window_ids integer[]
---@return State
function profile_state.forget_windows(state, window_ids)
    local removed = to_set(window_ids)
    local updated = deep_copy.copy(state)
    for _, profile in pairs(updated.profiles) do
        profile.window_ids = without(profile.window_ids, removed)
    end
    return updated
end

---Adds the windows to one profile, and leaves them in the other profiles that hold them.
---@param state State
---@param number integer
---@param window_ids integer[]
---@return State
function profile_state.add_windows(state, number, window_ids)
    check_profile_number(number)
    local profile = profile_state.profile_or_default(state, number)
    local held = to_set(profile.window_ids)
    for _, window_id in ipairs(window_ids) do
        if not held[window_id] then
            held[window_id] = true
            table.insert(profile.window_ids, window_id)
        end
    end
    return profile_state.with_profile(state, profile)
end

---Removes the windows from one profile, and leaves them in the other profiles that hold them.
---@param state State
---@param number integer
---@param window_ids integer[]
---@return State
function profile_state.remove_windows(state, number, window_ids)
    check_profile_number(number)
    local profile = profile_state.profile_or_default(state, number)
    profile.window_ids = without(profile.window_ids, to_set(window_ids))
    return profile_state.with_profile(state, profile)
end

---@param state State
---@return table<integer, integer[]> the numbers of the profiles that hold each window, ascending
function profile_state.holders_by_window_id(state)
    local holders = {}
    for _, profile in pairs(state.profiles) do
        for _, window_id in ipairs(profile.window_ids) do
            holders[window_id] = holders[window_id] or {}
            table.insert(holders[window_id], profile.number)
        end
    end
    for _, numbers in pairs(holders) do
        table.sort(numbers)
    end
    return holders
end

---@param state State
---@param number integer
---@param window_id integer
---@return boolean
function profile_state.holds_window(state, number, window_id)
    local profile = state.profiles[key_of(number)]
    if not profile then
        return false
    end
    for _, held_id in ipairs(profile.window_ids) do
        if held_id == window_id then
            return true
        end
    end
    return false
end

---@param state State
---@param number integer
---@param arrangement Arrangement
---@return State
function profile_state.with_arrangement(state, number, arrangement)
    local profile = profile_state.profile_or_default(state, number)
    profile.arrangements[arrangement.monitor_configuration_key] = deep_copy.copy(arrangement)
    return profile_state.with_profile(state, profile)
end

---@param state State
---@param number integer
---@param monitor_configuration_key string
---@return Arrangement|nil
function profile_state.find_arrangement(state, number, monitor_configuration_key)
    local profile = state.profiles[key_of(number)]
    local arrangement = profile and profile.arrangements[monitor_configuration_key]
    return arrangement and deep_copy.copy(arrangement) or nil
end

---Whole numbers decoded from JSON may arrive as floats, such as 3.0, and a float key would miss.
---@param value any
---@return integer|nil
local function to_integer(value)
    return type(value) == "number" and math.tointeger(value) or nil
end

---@param raw_records any
---@return WindowRecord[]
local function decode_window_records(raw_records)
    local records = {}
    for _, raw in ipairs(type(raw_records) == "table" and raw_records or {}) do
        if type(raw.bundle_id) == "string" then
            table.insert(records, {
                window_id = to_integer(raw.window_id),
                bundle_id = raw.bundle_id,
                app_name = tostring(raw.app_name or raw.bundle_id),
                title = tostring(raw.title or ""),
                slot_key = type(raw.slot_key) == "string" and raw.slot_key or nil,
                desktop_number = to_integer(raw.desktop_number),
                unit_frame = type(raw.unit_frame) == "table" and raw.unit_frame or nil,
                is_minimized = raw.is_minimized == true,
            })
        end
    end
    return records
end

---@param raw any
---@return Arrangement|nil
local function decode_arrangement(raw)
    if type(raw) ~= "table" or type(raw.monitor_configuration_key) ~= "string" then
        return nil
    end
    local monitors = {}
    for _, raw_monitor in ipairs(type(raw.monitors) == "table" and raw.monitors or {}) do
        local desktop_count = to_integer(raw_monitor.desktop_count)
        if type(raw_monitor.slot_key) == "string" and desktop_count then
            table.insert(
                monitors,
                { slot_key = raw_monitor.slot_key, desktop_count = desktop_count }
            )
        end
    end
    local focus = nil
    if type(raw.focus) == "table" and type(raw.focus.slot_key) == "string" then
        local desktop_number = to_integer(raw.focus.desktop_number)
        focus = desktop_number
            and { slot_key = raw.focus.slot_key, desktop_number = desktop_number }
    end
    return {
        monitor_configuration_key = raw.monitor_configuration_key,
        monitors = monitors,
        focus = focus,
        windows = decode_window_records(raw.windows),
    }
end

---@param raw any
---@return Profile|nil
local function decode_profile(raw)
    local number = type(raw) == "table" and to_integer(raw.number)
    if not number or number < 1 then
        return nil
    end
    local profile = new_profile(number)
    if type(raw.name) == "string" and raw.name ~= "" then
        profile.name = raw.name
    end
    for _, raw_window_id in ipairs(type(raw.window_ids) == "table" and raw.window_ids or {}) do
        local window_id = to_integer(raw_window_id)
        if window_id then
            table.insert(profile.window_ids, window_id)
        end
    end
    local raw_arrangements = type(raw.arrangements) == "table" and raw.arrangements or {}
    for key, raw_arrangement in pairs(raw_arrangements) do
        local arrangement = decode_arrangement(raw_arrangement)
        if arrangement and arrangement.monitor_configuration_key == key then
            profile.arrangements[key] = arrangement
        end
    end
    return profile
end

---Reads a state decoded from JSON, and drops the parts that do not have the expected shape.
---@param raw any
---@return State|nil state
---@return string|nil error_message
function profile_state.decode(raw)
    if type(raw) ~= "table" then
        return nil, string.format("the saved state is a %s, and a table was expected", type(raw))
    end
    if to_integer(raw.format_version) ~= profile_state.FORMAT_VERSION then
        return nil,
            string.format(
                "the saved state has format version %s, and this version reads %d",
                tostring(raw.format_version),
                profile_state.FORMAT_VERSION
            )
    end
    if not monitor_matching.is_valid(raw.monitor_matching) then
        return nil,
            string.format(
                "the saved state has the unknown monitor matching %q",
                tostring(raw.monitor_matching)
            )
    end
    local state = profile_state.new_state(raw.monitor_matching)
    for _, raw_profile in pairs(type(raw.profiles) == "table" and raw.profiles or {}) do
        local profile = decode_profile(raw_profile)
        if profile then
            state.profiles[key_of(profile.number)] = profile
        end
    end
    local active_number = to_integer(raw.active_profile_number)
    if active_number and active_number >= 1 then
        state.active_profile_number = active_number
    end
    return state, nil
end

return profile_state
