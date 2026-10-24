local app_pool = require("desktop_manager.core.app_pool")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local profile_state = require("desktop_manager.core.profile_state")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local retained_timers = require("desktop_manager.macos.retained_timers")
local track_windows = require("desktop_manager.macos.track_windows")

---The lines of the diagnostics, block by block, from what the desktop manager reads of
---Hammerspoon, the screens, the desktops, the windows and the state, without changing anything.
local diagnostic_lines = {}

---@param lines string[]
---@param format string
---@param ... any
local function add(lines, format, ...)
    table.insert(lines, string.format(format, ...))
end

---@param state State
---@return string[] the build and the permission of Hammerspoon, the timers, the monitor matching
---and the pool of managed applications
function diagnostic_lines.describe_build(state)
    local lines = {}
    add(lines, "Hammerspoon %s", tostring(hs.processInfo and hs.processInfo.version))
    add(lines, "accessibility permission: %s", tostring(hs.accessibilityState()))
    add(lines, "running timers: %d", retained_timers.count_running())
    add(lines, "monitor matching: %s", state.monitor_matching)
    add(lines, "application pool: %s", app_pool.describe(state.app_pool))
    return lines
end

---@param configuration MonitorConfiguration
---@param builtin_screen_name_patterns string[]
---@return string[] the monitor configuration and the slot of each screen
function diagnostic_lines.describe_screens(configuration, builtin_screen_name_patterns)
    local lines = {}
    add(lines, "monitor configuration: %s", configuration.key)
    for _, screen in ipairs(read_screens.describe_screens(builtin_screen_name_patterns)) do
        local slot = monitor_configuration.find_slot_of_screen(configuration, screen.uuid)
        add(
            lines,
            "  screen %s %q built-in=%s slot=%s",
            screen.uuid,
            screen.name,
            tostring(screen.is_builtin),
            slot.slot_key
        )
    end
    return lines
end

---@param configuration MonitorConfiguration
---@return string[] the desktops of each screen with the one it shows, and the focused desktop
function diagnostic_lines.describe_desktops(configuration)
    local lines = {}
    local layout = read_desktops.read_desktop_layout()
    for _, screen in ipairs(layout.screens) do
        local numbered, shown = {}, nil
        for position, space_id in ipairs(screen.space_ids) do
            table.insert(numbered, string.format("%d=%d", position, space_id))
            if space_id == screen.active_space_id then
                shown = tostring(position)
            end
        end
        local slot = monitor_configuration.find_slot_of_screen(configuration, screen.screen_uuid)
        add(
            lines,
            "  desktops of %s (%s): %s, shown %s",
            screen.screen_uuid,
            slot and slot.slot_key or "no slot",
            table.concat(numbered, " "),
            shown or string.format("space %s", tostring(screen.active_space_id))
        )
    end
    add(lines, "focused desktop: %s", tostring(layout.focused_space_id))
    return lines
end

---@param state State
---@param active_arrangement Arrangement|nil the arrangement of the active profile for the monitor
---configuration
---@return string[] the desktops kept per display, the active profile, and the desktops and the
---focus that its arrangement records
function diagnostic_lines.describe_profile(state, active_arrangement)
    local lines = {}
    local kept_counts = {}
    for slot_key, count in pairs(state.desktop_counts.kept) do
        table.insert(kept_counts, string.format("%s %d", slot_key, count))
    end
    table.sort(kept_counts)
    add(lines, "desktops kept per display: %s", table.concat(kept_counts, ", "))
    add(lines, "active profile: %s", tostring(state.active_profile_number))
    local active_number = state.active_profile_number
    for _, monitor in ipairs(active_arrangement and active_arrangement.monitors or {}) do
        add(
            lines,
            monitor.shown_desktop_number
                    and "profile %d holds %d desktops on %s and shows desktop %d"
                or "profile %d holds %d desktops on %s and records no desktop shown",
            active_number,
            monitor.desktop_count,
            monitor.slot_key,
            monitor.shown_desktop_number
        )
    end
    if active_arrangement and active_arrangement.focused_slot_key then
        add(
            lines,
            "profile %d had the focus on %s",
            active_number,
            active_arrangement.focused_slot_key
        )
    end
    return lines
end

---@param numbering_profile Profile the profile whose application numbers hold
---@return string[] the application numbers of the profile
function diagnostic_lines.describe_app_numbers(numbering_profile)
    local lines = {}
    add(lines, "application numbers of %s:", numbering_profile.name)
    for _, entry in ipairs(numbering_profile.app_numbers) do
        add(
            lines,
            "  app number %d: %s %s%s",
            entry.number,
            entry.app_name,
            entry.bundle_id,
            entry.is_chosen_by_user and " (chosen)" or ""
        )
    end
    return lines
end

---@param state State
---@param profile_count integer
---@param configuration_key string
---@return table<integer, table<integer, WindowRecord>> the records of each profile for the monitor
---configuration, by window id
local function index_records_by_profile(state, profile_count, configuration_key)
    local records_by_profile = {}
    for number = 1, profile_count do
        local arrangement = profile_state.find_arrangement(state, number, configuration_key)
        records_by_profile[number] = {}
        for _, record in ipairs(arrangement and arrangement.windows or {}) do
            if record.window_id then
                records_by_profile[number][record.window_id] = record
            end
        end
    end
    return records_by_profile
end

---@param state State
---@param profile_count integer
---@param configuration_key string
---@param active_arrangement Arrangement|nil
---@param known_windows KnownWindows
---@param window_filter table an hs.window.filter
---@return string[] the number of the windows out of reach, and each window of a managed
---application with what the desktop manager reads of it and the profiles that recorded it
function diagnostic_lines.describe_windows(
    state,
    profile_count,
    configuration_key,
    active_arrangement,
    known_windows,
    window_filter
)
    local lines = {}
    local records_by_profile = index_records_by_profile(state, profile_count, configuration_key)
    local listed = track_windows.index_by_id(window_filter:getWindows())
    local managed_windows =
        known_windows:list_managed(profile_state.list_recorded_window_ids(active_arrangement))
    add(lines, "windows out of reach: %d", #known_windows:list_unreached_managed(managed_windows))
    for _, window in ipairs(managed_windows) do
        local observation = track_windows.observe(window)
        local recorded_states = {}
        for number = 1, profile_count do
            local record = records_by_profile[number][observation.window_id]
            if record then
                local sight = record.is_out_of_sight and "out of sight" or "in sight"
                table.insert(recorded_states, string.format("%d %s", number, sight))
            end
        end
        add(
            lines,
            "  window %s %s %q desktop=%s out-of-sight=%s in-filter=%s recorded=%s",
            tostring(observation.window_id),
            observation.bundle_id,
            observation.title,
            tostring(observation.space_id),
            tostring(observation.is_out_of_sight),
            tostring(listed[observation.window_id] ~= nil),
            table.concat(recorded_states, ", ")
        )
    end
    return lines
end

return diagnostic_lines
