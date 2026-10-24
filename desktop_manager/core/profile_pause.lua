---The pause of the active profile at the first start of Hammerspoon soon after the start of macOS,
---when macOS reopens the windows with new ids and at places of its own.
local profile_pause = {}

---@param boot_time_output string|nil the output of `sysctl -n kern.boottime`, such as
---"{ sec = 1729500000, usec = 12345 } Mon Oct 21 10:40:00 2024"
---@return integer|nil the start of macOS in seconds since 1970, or nil when the output gives none
function profile_pause.parse_macos_start_time(boot_time_output)
    local seconds = type(boot_time_output) == "string" and boot_time_output:match("sec = (%d+)")
    return seconds and math.tointeger(tonumber(seconds)) or nil
end

---A start under a start of macOS that the state file already saw pauses nothing, so a Reload
---Config after the user ended the pause keeps the updates going.
---A start of macOS that could not be read counts as a new one, because a pause that was not needed
---costs one press, and an update after a restart replaces the record of the profile.
---@param state State
---@param macos_start_time integer|nil the start of macOS in seconds since 1970, or nil when unknown
---@param seconds_since_macos_start number the time since the start of macOS, without the time
---asleep
---@param pause_after_macos_start_seconds number the setting, 0 when a start never pauses
---@return boolean whether the start pauses the active profile
function profile_pause.is_due_at_start(
    state,
    macos_start_time,
    seconds_since_macos_start,
    pause_after_macos_start_seconds
)
    local is_first_start_after_macos_start = macos_start_time == nil
        or macos_start_time ~= state.last_seen_macos_start_time
    return state.active_profile_number ~= nil
        and not state.is_active_profile_paused
        and is_first_start_after_macos_start
        and seconds_since_macos_start < pause_after_macos_start_seconds
end

---@param number integer the paused profile
---@param seconds_since_macos_start number
---@param pause_after_macos_start_seconds number
---@return string the line of the console at the start that pauses the profile
function profile_pause.describe_start_pause(
    number,
    seconds_since_macos_start,
    pause_after_macos_start_seconds
)
    return string.format(
        "profile %d is paused, because Hammerspoon started %.0f seconds after macOS, less than"
            .. " pause_after_macos_start_seconds of %g, and activating profile %d restores its"
            .. " layout",
        number,
        seconds_since_macos_start,
        pause_after_macos_start_seconds,
        number
    )
end

---@param number integer the paused profile
---@return string the line of the console at a start that finds the pause in the state file
function profile_pause.describe_kept_pause(number)
    return string.format(
        "profile %d stays paused, as the state file says, and activating profile %d restores its"
            .. " layout",
        number,
        number
    )
end

return profile_pause
