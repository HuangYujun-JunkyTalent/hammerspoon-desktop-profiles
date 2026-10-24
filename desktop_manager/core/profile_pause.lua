---The pause of the active profile at the first start of Hammerspoon soon after a login, when macOS
---reopens the windows with new ids and at places of its own.
local profile_pause = {}

---@param boot_time_output string|nil the output of `sysctl -n kern.boottime`, such as
---"{ sec = 1729500000, usec = 12345 } Mon Oct 21 10:40:00 2024"
---@return integer|nil the start of macOS in seconds since 1970, or nil when the output gives none
function profile_pause.parse_macos_start_time(boot_time_output)
    local seconds = type(boot_time_output) == "string" and boot_time_output:match("sec = (%d+)")
    return seconds and math.tointeger(tonumber(seconds)) or nil
end

---The months as `who` names them under the locale C.
local MONTH_NUMBERS = {
    Jan = 1,
    Feb = 2,
    Mar = 3,
    Apr = 4,
    May = 5,
    Jun = 6,
    Jul = 7,
    Aug = 8,
    Sep = 9,
    Oct = 10,
    Nov = 11,
    Dec = 12,
}

---The login of the user to the console, which macOS records at each login, also at the login
---after a start of macOS.
---@class Login
---@field time integer the minute of the login, in seconds since 1970
---@field seconds_since integer the seconds from that minute to the reading

---`who` dates a login without the year, so a login that the year of the reading would date after
---the reading lies in the year before.
---@param reading_time integer the time of the reading, in seconds since 1970
---@param login_date table the `month`, `day`, `hour` and `min` of the login, as `who` gives them
---@return integer the minute of the login, in seconds since 1970, in the time zone of the Mac
local function find_login_time(reading_time, login_date)
    local function find_time_in(year)
        return os.time({
            year = year,
            month = login_date.month,
            day = login_date.day,
            hour = login_date.hour,
            min = login_date.min,
            sec = 0,
        })
    end
    local reading_year = math.tointeger(tonumber(os.date("%Y", reading_time)))
    local time = find_time_in(reading_year)
    if time > reading_time then
        return find_time_in(reading_year - 1)
    end
    return time
end

---@param login_output string|nil the output of `id -un; date +%s; LC_ALL=C who`: the name of the
---user, the time of the reading in seconds since 1970, and one line per session, such as
---"jane     console      Oct  4 20:59 "
---@return Login|nil the latest console login of the user, or nil when the output gives none
function profile_pause.parse_login(login_output)
    if type(login_output) ~= "string" then
        return nil
    end
    local user, reading_text, sessions = login_output:match("^([^\n]+)\n(%d+)\n(.*)$")
    local reading_time = reading_text and math.tointeger(tonumber(reading_text))
    if not reading_time then
        return nil
    end
    local latest_time = nil
    for line in sessions:gmatch("[^\n]+") do
        local name, month, day, hour, minute =
            line:match("^(%S+)%s+console%s+(%a%a%a)%s+(%d+)%s+(%d%d):(%d%d)")
        if name == user and MONTH_NUMBERS[month] then
            local time = find_login_time(reading_time, {
                month = MONTH_NUMBERS[month],
                day = tonumber(day),
                hour = tonumber(hour),
                min = tonumber(minute),
            })
            latest_time = math.max(time, latest_time or time)
        end
    end
    if not latest_time then
        return nil
    end
    return { time = latest_time, seconds_since = reading_time - latest_time }
end

---What a start of the desktop manager reads of the login of the user and of the start of macOS.
---@class StartReading
---@field login Login|nil the login, or nil when `who` gives none
---@field macos_start_time integer|nil the start of macOS in seconds since 1970, or nil when
---`sysctl` gives none
---@field seconds_since_macos_start number the time since the start of macOS, without the time
---asleep

---A start under a login that the state file already saw pauses nothing, so a Reload Config after
---the user ended the pause keeps the updates going.
---A start that reads no login falls back to the start of macOS, and a start of macOS that could
---not be read counts as a new one, because a pause that was not needed costs one press, and an
---update after a restart replaces the record of the profile.
---@param state State
---@param reading StartReading
---@return boolean whether no earlier start saw the login, or the start of macOS when no login was
---read
local function is_first_start(state, reading)
    if reading.login then
        return reading.login.time ~= state.last_seen_login_time
    end
    return reading.macos_start_time == nil
        or reading.macos_start_time ~= state.last_seen_macos_start_time
end

---@param reading StartReading
---@return number the seconds since the login, or since the start of macOS when no login was read
local function count_seconds_since_login_or_macos_start(reading)
    if reading.login then
        return reading.login.seconds_since
    end
    return reading.seconds_since_macos_start
end

---@param state State
---@param reading StartReading
---@param pause_after_login_seconds number the setting, 0 when a start never pauses
---@return boolean whether the start pauses the active profile
function profile_pause.is_due_at_start(state, reading, pause_after_login_seconds)
    return state.active_profile_number ~= nil
        and not state.is_active_profile_paused
        and is_first_start(state, reading)
        and count_seconds_since_login_or_macos_start(reading) < pause_after_login_seconds
end

---@param number integer the paused profile
---@param reading StartReading
---@param pause_after_login_seconds number
---@return string the line of the console at the start that pauses the profile
function profile_pause.describe_start_pause(number, reading, pause_after_login_seconds)
    return string.format(
        "profile %d is paused, because Hammerspoon started %.0f seconds after %s, less than"
            .. " pause_after_login_seconds of %g, and activating profile %d restores its"
            .. " layout",
        number,
        count_seconds_since_login_or_macos_start(reading),
        reading.login and "the login" or "macOS",
        pause_after_login_seconds,
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
