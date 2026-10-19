local app_pool = require("desktop_manager.core.app_pool")
local deep_copy = require("desktop_manager.core.deep_copy")
local desktop_counts = require("desktop_manager.core.desktop_counts")
local highlight_colors = require("desktop_manager.core.highlight_colors")
local monitor_matching = require("desktop_manager.core.monitor_matching")

local profile_state = {}

---A profile holds the desktops and windows it recorded, one arrangement per monitor configuration.
---@class Profile
---@field number integer
---@field name string
---@field arrangements table<string, Arrangement> keyed by monitor configuration key
---@field app_numbers AppNumber[] the applications that shortcuts such as Control-Option-3 reach

---The state that the tool keeps between runs of Hammerspoon.
---Profiles are keyed by their number written as a string, because JSON objects have string keys.
---@class State
---@field format_version integer
---@field monitor_matching string
---@field active_profile_number integer|nil
---@field profiles table<string, Profile>
---@field app_pool AppPool the applications that every profile manages
---@field desktop_counts DesktopCounts the number of desktops of each display
---@field highlight_colors table<string, table> the colors of the search that the window of the
---colors chose, by the names of highlight_colors, over the setting `search_highlight_colors`

---Version 2 records the shown desktop of each screen and the screen of the focus, where version 1
---recorded the desktop in front, and records the number of desktops that each screen had.
profile_state.FORMAT_VERSION = 2

---A state of this version is read through a migration.
local FIRST_FORMAT_VERSION = 1

---Profile 0 holds the application numbers that the shortcuts reach while no profile is active.
---It records no windows, because a window that a profile records goes out of sight when another
---profile is activated.
profile_state.NO_PROFILE_NUMBER = 0

---@param number any
local function check_profile_number(number)
    if math.type(number) ~= "integer" or number < 0 then
        error(
            string.format(
                "a profile number is a whole number of 0 or more, and %s was given",
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
        arrangements = {},
        app_numbers = {},
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
        app_pool = app_pool.new(),
        desktop_counts = desktop_counts.new(),
        highlight_colors = {},
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
    if number == profile_state.NO_PROFILE_NUMBER then
        error("profile 0 holds the numbers of no active profile, and cannot be activated", 2)
    end
    local updated = deep_copy.copy(state)
    updated.active_profile_number = number
    return updated
end

---@param state State
---@return integer the profile whose application numbers the shortcuts reach: the active profile,
---or profile 0 while no profile is active
function profile_state.find_numbering_profile_number(state)
    return state.active_profile_number or profile_state.NO_PROFILE_NUMBER
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

---Removes the records of every monitor configuration of the profile, and keeps its name and its
---application numbers.
---@param state State
---@param number integer
---@return State
function profile_state.clear_arrangements(state, number)
    if number == profile_state.NO_PROFILE_NUMBER then
        error("profile 0 records no windows", 2)
    end
    local profile = profile_state.profile_or_default(state, number)
    profile.arrangements = {}
    return profile_state.with_profile(state, profile)
end

---@param state State
---@param number integer
---@return boolean whether the profile recorded some monitor configuration
function profile_state.has_arrangements(state, number)
    local profile = state.profiles[key_of(number)]
    return profile ~= nil and next(profile.arrangements) ~= nil
end

---@param state State
---@param pool AppPool
---@return State
function profile_state.with_app_pool(state, pool)
    local updated = deep_copy.copy(state)
    updated.app_pool = deep_copy.copy(pool)
    return updated
end

---@param state State
---@param colors table<string, table> the colors of the search that the window of the colors chose
---@return State
function profile_state.with_highlight_colors(state, colors)
    local updated = deep_copy.copy(state)
    updated.highlight_colors = deep_copy.copy(colors)
    return updated
end

---@param state State
---@param counts DesktopCounts
---@return State
function profile_state.with_desktop_counts(state, counts)
    local updated = deep_copy.copy(state)
    updated.desktop_counts = deep_copy.copy(counts)
    return updated
end

---The windows that some arrangement of some profile records.
---The application is part of the key, because macOS reuses window ids after a restart.
---@param state State
---@return table<integer, table<string, boolean>> the applications recorded for each window id
function profile_state.index_recorded_windows(state)
    local recorded = {}
    for _, profile in pairs(state.profiles) do
        for _, arrangement in pairs(profile.arrangements) do
            for _, record in ipairs(arrangement.windows) do
                if record.window_id then
                    recorded[record.window_id] = recorded[record.window_id] or {}
                    recorded[record.window_id][record.bundle_id] = true
                end
            end
        end
    end
    return recorded
end

---@param state State
---@return WindowRecord[] the records of every arrangement of every profile
function profile_state.list_all_records(state)
    local records = {}
    for _, profile in pairs(state.profiles) do
        for _, arrangement in pairs(profile.arrangements) do
            for _, record in ipairs(arrangement.windows) do
                table.insert(records, deep_copy.copy(record))
            end
        end
    end
    return records
end

---A window rename gives the records of a window that its application reopened the new id.
---@class WindowRename
---@field bundle_id string
---@field old_window_id integer
---@field new_window_id integer

---Writes the new window ids into the records of every profile.
---@param state State
---@param renames WindowRename[]
---@return State
function profile_state.rename_windows(state, renames)
    local updated = deep_copy.copy(state)
    for _, profile in pairs(updated.profiles) do
        for _, arrangement in pairs(profile.arrangements) do
            for _, record in ipairs(arrangement.windows) do
                for _, rename in ipairs(renames) do
                    if
                        record.window_id == rename.old_window_id
                        and record.bundle_id == rename.bundle_id
                    then
                        record.window_id = rename.new_window_id
                    end
                end
            end
        end
    end
    return updated
end

---@param state State
---@param number integer
---@param arrangement Arrangement
---@return State
function profile_state.with_arrangement(state, number, arrangement)
    if number == profile_state.NO_PROFILE_NUMBER then
        error("profile 0 records no windows", 2)
    end
    local profile = profile_state.profile_or_default(state, number)
    profile.arrangements[arrangement.monitor_configuration_key] = deep_copy.copy(arrangement)
    return profile_state.with_profile(state, profile)
end

---@param state State
---@param number integer
---@param entries AppNumber[]
---@return State
function profile_state.with_app_numbers(state, number, entries)
    local profile = profile_state.profile_or_default(state, number)
    profile.app_numbers = deep_copy.copy(entries)
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
                is_out_of_sight = raw.is_out_of_sight == true or raw.is_minimized == true,
            })
        end
    end
    return records
end

---@param value any
---@return integer|nil a desktop number of 1 or more
local function to_desktop_number(value)
    local number = to_integer(value)
    return number and number >= 1 and number or nil
end

---@param records WindowRecord[]
---@param slot_key string
---@return integer the highest desktop number of a record on the slot, or 0
local function find_highest_desktop_number(records, slot_key)
    local highest = 0
    for _, record in ipairs(records) do
        if record.slot_key == slot_key and record.desktop_number then
            highest = math.max(highest, record.desktop_number)
        end
    end
    return highest
end

---Version 1 recorded the kept number of desktops of a slot or the raw number, which holds the
---desktops that macOS moved from a display that disconnected.
---Each number becomes at most the larger of the kept number of its slot and the highest desktop of
---a record on the slot, and a slot without a kept number keeps its number.
---The desktop in front becomes the shown desktop of its screen and the screen of the focus.
---@param arrangement Arrangement
---@param raw_focus any the field `focus` of version 1
---@param kept_counts table<string, integer>
local function migrate_first_version(arrangement, raw_focus, kept_counts)
    for _, monitor in ipairs(arrangement.monitors) do
        local kept_count = kept_counts[monitor.slot_key]
        if kept_count then
            local needed_count = math.max(
                kept_count,
                find_highest_desktop_number(arrangement.windows, monitor.slot_key)
            )
            monitor.desktop_count = math.min(monitor.desktop_count, needed_count)
        end
    end
    local focus_number = type(raw_focus) == "table" and to_desktop_number(raw_focus.desktop_number)
    if not focus_number or type(raw_focus.slot_key) ~= "string" then
        return
    end
    for _, monitor in ipairs(arrangement.monitors) do
        if monitor.slot_key == raw_focus.slot_key then
            monitor.shown_desktop_number = focus_number
            arrangement.focused_slot_key = raw_focus.slot_key
        end
    end
end

---@param raw any
---@param format_version integer
---@param kept_counts table<string, integer> the kept numbers of desktops, for the migration
---@return Arrangement|nil
local function decode_arrangement(raw, format_version, kept_counts)
    if type(raw) ~= "table" or type(raw.monitor_configuration_key) ~= "string" then
        return nil
    end
    local monitors = {}
    for _, raw_monitor in ipairs(type(raw.monitors) == "table" and raw.monitors or {}) do
        local desktop_count = to_integer(raw_monitor.desktop_count)
        if type(raw_monitor.slot_key) == "string" and desktop_count then
            table.insert(monitors, {
                slot_key = raw_monitor.slot_key,
                desktop_count = desktop_count,
                shown_desktop_number = to_desktop_number(raw_monitor.shown_desktop_number),
            })
        end
    end
    local arrangement = {
        monitor_configuration_key = raw.monitor_configuration_key,
        monitors = monitors,
        focused_slot_key = type(raw.focused_slot_key) == "string" and raw.focused_slot_key or nil,
        windows = decode_window_records(raw.windows),
    }
    if format_version == FIRST_FORMAT_VERSION then
        migrate_first_version(arrangement, raw.focus, kept_counts)
    end
    return arrangement
end

---@param raw_entries any
---@return AppNumber[]
local function decode_app_numbers(raw_entries)
    local entries = {}
    for _, raw in ipairs(type(raw_entries) == "table" and raw_entries or {}) do
        local number = to_integer(raw.number)
        if number and type(raw.bundle_id) == "string" then
            table.insert(entries, {
                number = number,
                bundle_id = raw.bundle_id,
                app_name = tostring(raw.app_name or raw.bundle_id),
                is_chosen_by_user = raw.is_chosen_by_user == true,
            })
        end
    end
    return entries
end

---@param raw any
---@param format_version integer
---@param kept_counts table<string, integer>
---@return Profile|nil
local function decode_profile(raw, format_version, kept_counts)
    local number = type(raw) == "table" and to_integer(raw.number)
    if not number or number < 0 then
        return nil
    end
    local profile = new_profile(number)
    if type(raw.name) == "string" and raw.name ~= "" then
        profile.name = raw.name
    end
    profile.app_numbers = decode_app_numbers(raw.app_numbers)
    if number == profile_state.NO_PROFILE_NUMBER then
        return profile
    end
    local raw_arrangements = type(raw.arrangements) == "table" and raw.arrangements or {}
    for key, raw_arrangement in pairs(raw_arrangements) do
        local arrangement = decode_arrangement(raw_arrangement, format_version, kept_counts)
        if arrangement and arrangement.monitor_configuration_key == key then
            profile.arrangements[key] = arrangement
        end
    end
    return profile
end

---@param raw_counts any
---@return table<string, integer> the counts of at least 1, by slot key
local function decode_counts_by_slot(raw_counts)
    local counts = {}
    for slot_key, raw_count in pairs(type(raw_counts) == "table" and raw_counts or {}) do
        local count = to_integer(raw_count)
        if type(slot_key) == "string" and count and count >= 1 then
            counts[slot_key] = count
        end
    end
    return counts
end

---@param raw any
---@return DesktopCounts
local function decode_desktop_counts(raw)
    local counts = desktop_counts.new()
    if type(raw) ~= "table" then
        return counts
    end
    counts.kept = decode_counts_by_slot(raw.kept)
    local reading = raw.last_reading
    if type(reading) == "table" and type(reading.displays_key) == "string" then
        counts.last_reading = {
            displays_key = reading.displays_key,
            counts = decode_counts_by_slot(reading.counts),
        }
    end
    return counts
end

---Reads a state decoded from JSON, and drops the parts that do not have the expected shape.
---A state of format version 1 is migrated, as `migrate_first_version` says.
---@param raw any
---@return State|nil state
---@return string|nil error_message
function profile_state.decode(raw)
    if type(raw) ~= "table" then
        return nil, string.format("the saved state is a %s, and a table was expected", type(raw))
    end
    local format_version = to_integer(raw.format_version) or 0
    if
        format_version ~= profile_state.FORMAT_VERSION
        and format_version ~= FIRST_FORMAT_VERSION
    then
        return nil,
            string.format(
                "the saved state has format version %s, and this version reads %d to %d",
                tostring(raw.format_version),
                FIRST_FORMAT_VERSION,
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
    state.desktop_counts = decode_desktop_counts(raw.desktop_counts)
    for _, raw_profile in pairs(type(raw.profiles) == "table" and raw.profiles or {}) do
        local profile = decode_profile(raw_profile, format_version, state.desktop_counts.kept)
        if profile then
            state.profiles[key_of(profile.number)] = profile
        end
    end
    local active_number = to_integer(raw.active_profile_number)
    if active_number and active_number >= 1 then
        state.active_profile_number = active_number
    end
    state.app_pool = app_pool.decode(raw.app_pool, raw.managed_applications)
    state.highlight_colors = highlight_colors.decode(raw.highlight_colors)
    return state, nil
end

return profile_state
