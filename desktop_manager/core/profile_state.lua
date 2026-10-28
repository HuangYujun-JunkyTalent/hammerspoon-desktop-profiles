local app_numbers = require("desktop_manager.core.app_numbers")
local app_pool = require("desktop_manager.core.app_pool")
local deep_copy = require("desktop_manager.core.deep_copy")
local desktop_counts = require("desktop_manager.core.desktop_counts")
local highlight_colors = require("desktop_manager.core.highlight_colors")
local live_settings = require("desktop_manager.core.live_settings")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local utf8_text = require("desktop_manager.core.utf8_text")

local profile_state = {}

---A profile holds the desktops and windows it recorded, one arrangement per monitor configuration.
---@class Profile
---@field number integer
---@field name string
---@field arrangements table<string, Arrangement> keyed by monitor configuration key
---@field app_numbers AppNumber[] the applications that shortcuts such as Control-Option-3 reach
---@field unmanaged_configuration_keys string[] the monitor configurations whose windows and
---desktops the profile leaves to macOS while it is active, in sorted order

---The state that the tool keeps between runs of Hammerspoon.
---Profiles are keyed by their number written as a string, because JSON objects have string keys.
---@class State
---@field format_version integer
---@field monitor_matching string
---@field active_profile_number integer|nil
---@field is_active_profile_paused boolean whether the updates leave the records and the application
---numbers of the active profile as they are, after a start of Hammerspoon soon after a login
---@field last_seen_macos_start_time integer|nil the start of macOS, in seconds since 1970, that the
---last start of the desktop manager saw, so that a start that reads no login pauses the active
---profile only when it is the first after a start of macOS
---@field last_seen_login_time integer|nil the minute of the login of the user, in seconds since
---1970, that the last start of the desktop manager saw, so that only the first start after a login
---pauses the active profile
---@field profiles table<string, Profile>
---@field app_pool AppPool the applications that every profile manages
---@field desktop_counts DesktopCounts the number of desktops of each display
---@field highlight_colors table<string, table> the colors of the search that the window of the
---colors chose, by the names of highlight_colors, over the setting `search_highlight_colors`
---@field setting_overrides table<string, any> the settings that the window "Settings…" chose, by
---their names, over the values of `default_settings.lua`

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
        unmanaged_configuration_keys = {},
    }
end

---@param state State
---@param field string
---@param value any
---@return State a copy of the state with a copy of the value in the field
local function with_field(state, field, value)
    local updated = deep_copy.copy(state)
    updated[field] = deep_copy.copy(value)
    return updated
end

---@param matching string
---@return State
function profile_state.new_state(matching)
    monitor_matching.check(matching)
    return {
        format_version = profile_state.FORMAT_VERSION,
        monitor_matching = matching,
        active_profile_number = nil,
        is_active_profile_paused = false,
        profiles = {},
        app_pool = app_pool.new(),
        desktop_counts = desktop_counts.new(),
        highlight_colors = {},
        setting_overrides = {},
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
    local updated = with_field(state, "active_profile_number", number)
    updated.is_active_profile_paused = false
    return updated
end

---@param state State
---@return State a copy of the state in which the active profile is paused
function profile_state.with_active_profile_paused(state)
    if not state.active_profile_number then
        error("no profile is active, so no profile can be paused", 2)
    end
    return with_field(state, "is_active_profile_paused", true)
end

---@param state State
---@return State a copy of the state in which the updates write the records of the active profile
function profile_state.with_pause_ended(state)
    return with_field(state, "is_active_profile_paused", false)
end

---@param state State
---@param macos_start_time integer|nil
---@return State a copy of the state that keeps the start of macOS that this start of the desktop
---manager saw
function profile_state.with_last_seen_macos_start_time(state, macos_start_time)
    return with_field(state, "last_seen_macos_start_time", macos_start_time)
end

---@param state State
---@param login_time integer|nil
---@return State a copy of the state that keeps the login that this start of the desktop manager
---saw
function profile_state.with_last_seen_login_time(state, login_time)
    return with_field(state, "last_seen_login_time", login_time)
end

---@param state State
---@param number integer
---@param monitor_configuration_key string
---@return boolean whether the profile arranges the windows and the desktops of the configuration
function profile_state.manages_configuration(state, number, monitor_configuration_key)
    local profile = state.profiles[key_of(number)]
    for _, key in ipairs(profile and profile.unmanaged_configuration_keys or {}) do
        if key == monitor_configuration_key then
            return false
        end
    end
    return true
end

---@param profile Profile
---@param monitor_configuration_key string
---@return string[] the unmanaged keys of the profile without the configuration
local function list_other_unmanaged_keys(profile, monitor_configuration_key)
    local keys = {}
    for _, key in ipairs(profile.unmanaged_configuration_keys) do
        if key ~= monitor_configuration_key then
            table.insert(keys, key)
        end
    end
    return keys
end

---@param state State
---@param number integer
---@param monitor_configuration_key string
---@return State a copy of the state in which the profile arranges the configuration
function profile_state.with_configuration_managed(state, number, monitor_configuration_key)
    local profile = profile_state.profile_or_default(state, number)
    profile.unmanaged_configuration_keys =
        list_other_unmanaged_keys(profile, monitor_configuration_key)
    return profile_state.with_profile(state, profile)
end

---@param state State
---@param number integer
---@param monitor_configuration_key string
---@return State a copy of the state in which the profile leaves the configuration to macOS
function profile_state.with_configuration_left_to_macos(state, number, monitor_configuration_key)
    if number == profile_state.NO_PROFILE_NUMBER then
        error("profile 0 arranges no monitor configuration", 2)
    end
    local profile = profile_state.profile_or_default(state, number)
    local keys = list_other_unmanaged_keys(profile, monitor_configuration_key)
    table.insert(keys, monitor_configuration_key)
    table.sort(keys)
    profile.unmanaged_configuration_keys = keys
    return profile_state.with_profile(state, profile)
end

---@param state State
---@param monitor_configuration_key string the configuration of the monitors now
---@return integer|nil the profile whose records and numbers the updates write: the active profile,
---or nil while it is paused, while it leaves the configuration to macOS, or while no profile is
---active
function profile_state.find_profile_number_to_update(state, monitor_configuration_key)
    local number = state.active_profile_number
    if
        not number
        or state.is_active_profile_paused
        or not profile_state.manages_configuration(state, number, monitor_configuration_key)
    then
        return nil
    end
    return number
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
    monitor_matching.check(matching)
    return with_field(state, "monitor_matching", matching)
end

---@param state State
---@param number integer
---@param name string
---@return State
function profile_state.with_profile_name(state, number, name)
    local trimmed = type(name) == "string" and utf8_text.trim(name) or ""
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
    return with_field(state, "app_pool", pool)
end

---@param state State
---@param colors table<string, table> the colors of the search that the window of the colors chose
---@return State
function profile_state.with_highlight_colors(state, colors)
    return with_field(state, "highlight_colors", colors)
end

---@param state State
---@param overrides table<string, any>
---@return State
function profile_state.with_setting_overrides(state, overrides)
    return with_field(state, "setting_overrides", overrides)
end

---@param state State
---@param counts DesktopCounts
---@return State
function profile_state.with_desktop_counts(state, counts)
    return with_field(state, "desktop_counts", counts)
end

---@param state State
---@return WindowRecord[] the records of every arrangement of every profile, as the tables of the
---state itself
local function list_records_of_state(state)
    local records = {}
    for _, profile in pairs(state.profiles) do
        for _, arrangement in pairs(profile.arrangements) do
            for _, record in ipairs(arrangement.windows) do
                table.insert(records, record)
            end
        end
    end
    return records
end

---The windows that some arrangement of some profile records.
---The application is part of the key, because macOS reuses window ids after a restart.
---@param state State
---@return table<integer, table<string, boolean>> the applications recorded for each window id
function profile_state.index_recorded_windows(state)
    local recorded = {}
    for _, record in ipairs(list_records_of_state(state)) do
        if record.window_id then
            recorded[record.window_id] = recorded[record.window_id] or {}
            recorded[record.window_id][record.bundle_id] = true
        end
    end
    return recorded
end

---@param state State
---@return table<string, boolean> the applications that some record, some application number or the
---list of the managed applications of the pool names in its mode `MANAGE_LISTED`, by bundle id, and
---not the ticks of the other mode, which no profile follows
function profile_state.list_named_bundle_ids(state)
    local bundle_ids = {}
    for _, record in ipairs(list_records_of_state(state)) do
        bundle_ids[record.bundle_id] = true
    end
    for _, profile in pairs(state.profiles) do
        for _, entry in ipairs(profile.app_numbers) do
            bundle_ids[entry.bundle_id] = true
        end
    end
    if state.app_pool.mode == app_pool.MANAGE_LISTED then
        for _, listed in ipairs(state.app_pool.manage_listed) do
            bundle_ids[listed.bundle_id] = true
        end
    end
    return bundle_ids
end

---@param state State
---@return WindowRecord[] the records of every arrangement of every profile
function profile_state.list_all_records(state)
    local records = {}
    for _, record in ipairs(list_records_of_state(state)) do
        table.insert(records, deep_copy.copy(record))
    end
    return records
end

---A window rename gives the records of a window that its application reopened the new id.
---@class WindowRename
---@field bundle_id string
---@field old_window_id integer
---@field new_window_id integer

---@param record WindowRecord
---@param new_window_id integer
---@return WindowRename the rename of the window of the record to the new window id
function profile_state.rename_of(record, new_window_id)
    return {
        bundle_id = record.bundle_id,
        old_window_id = record.window_id,
        new_window_id = new_window_id,
    }
end

---Writes the new window ids into the records of every profile.
---@param state State
---@param renames WindowRename[]
---@return State
function profile_state.rename_windows(state, renames)
    local updated = deep_copy.copy(state)
    for _, record in ipairs(list_records_of_state(updated)) do
        for _, rename in ipairs(renames) do
            if
                record.window_id == rename.old_window_id
                and record.bundle_id == rename.bundle_id
            then
                record.window_id = rename.new_window_id
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

---Records the desktop as the desktop that the screen of the slot shows and the slot as the screen
---of the focus, in the arrangement of the profile for the monitor configuration.
---@param state State
---@param number integer
---@param monitor_configuration_key string
---@param slot_key string
---@param desktop_number integer
---@return State|nil the new state, or nil when the profile has no arrangement for the configuration
function profile_state.with_shown_desktop(
    state,
    number,
    monitor_configuration_key,
    slot_key,
    desktop_number
)
    local arrangement = profile_state.find_arrangement(state, number, monitor_configuration_key)
    if not arrangement then
        return nil
    end
    local recorded = deep_copy.copy(arrangement)
    for _, monitor in ipairs(recorded.monitors) do
        if monitor.slot_key == slot_key then
            monitor.shown_desktop_number = desktop_number
        end
    end
    recorded.focused_slot_key = slot_key
    return profile_state.with_arrangement(state, number, recorded)
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

---Updates the default application numbers of the profile from the windows of an arrangement.
---@param state State
---@param number integer
---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@param app_number_count integer
---@return State
function profile_state.with_default_app_numbers(
    state,
    number,
    arrangement,
    configuration,
    app_number_count
)
    return profile_state.with_app_numbers(
        state,
        number,
        app_numbers.update_defaults(
            profile_state.profile_or_default(state, number).app_numbers,
            arrangement,
            configuration,
            app_number_count
        )
    )
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

---@param arrangement Arrangement|nil
---@return integer[] the window ids that the arrangement records
function profile_state.list_recorded_window_ids(arrangement)
    local window_ids = {}
    for _, record in ipairs(arrangement and arrangement.windows or {}) do
        if record.window_id then
            table.insert(window_ids, record.window_id)
        end
    end
    return window_ids
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

---@param raw_keys any
---@return string[] the keys that are strings, each once, in sorted order
local function decode_configuration_keys(raw_keys)
    local keys, is_seen = {}, {}
    for _, key in ipairs(type(raw_keys) == "table" and raw_keys or {}) do
        if type(key) == "string" and not is_seen[key] then
            is_seen[key] = true
            table.insert(keys, key)
        end
    end
    table.sort(keys)
    return keys
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
    profile.unmanaged_configuration_keys =
        decode_configuration_keys(raw.unmanaged_configuration_keys)
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
        state.is_active_profile_paused = raw.is_active_profile_paused == true
    end
    state.last_seen_macos_start_time = to_integer(raw.last_seen_macos_start_time)
    state.last_seen_login_time = to_integer(raw.last_seen_login_time)
    state.app_pool = app_pool.decode(raw.app_pool, raw.managed_applications)
    state.highlight_colors = highlight_colors.decode(raw.highlight_colors)
    state.setting_overrides = live_settings.decode(raw.setting_overrides)
    return state, nil
end

return profile_state
