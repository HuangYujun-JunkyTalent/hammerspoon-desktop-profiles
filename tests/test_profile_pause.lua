local expect = require("tests.expect")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local profile_pause = require("desktop_manager.core.profile_pause")
local profile_state = require("desktop_manager.core.profile_state")

local MACOS_START_TIME = 1729500000
local EARLIER_MACOS_START_TIME = 1729400000
local LOGIN_TIME = 1729500060
local EARLIER_LOGIN_TIME = 1729400060

---@return State a state in which profile 1 is active, saved under an earlier login and an earlier
---start of macOS
local function build_active_state()
    return profile_state.with_last_seen_login_time(
        profile_state.with_last_seen_macos_start_time(
            profile_state.with_active_profile_number(
                profile_state.new_state(monitor_matching.BY_COUNT),
                1
            ),
            EARLIER_MACOS_START_TIME
        ),
        EARLIER_LOGIN_TIME
    )
end

---@param seconds_since_login number
---@return StartReading a start under the login `LOGIN_TIME`, an hour after the start of macOS
local function read_after_login(seconds_since_login)
    return {
        login = { time = LOGIN_TIME, seconds_since = seconds_since_login },
        macos_start_time = MACOS_START_TIME,
        seconds_since_macos_start = 3600,
    }
end

---@param macos_start_time integer|nil
---@param seconds_since_macos_start number
---@return StartReading a start that read no login
local function read_without_login(macos_start_time, seconds_since_macos_start)
    return {
        login = nil,
        macos_start_time = macos_start_time,
        seconds_since_macos_start = seconds_since_macos_start,
    }
end

return {
    a_start_before_the_setting_pauses_the_active_profile = function()
        local state = build_active_state()
        expect.equal(profile_pause.is_due_at_start(state, read_after_login(60), 300), true)
        expect.equal(profile_pause.is_due_at_start(state, read_after_login(299), 300), true)
    end,

    a_start_at_or_after_the_setting_pauses_nothing = function()
        local state = build_active_state()
        expect.equal(profile_pause.is_due_at_start(state, read_after_login(300), 300), false)
        expect.equal(profile_pause.is_due_at_start(state, read_after_login(3600), 300), false)
    end,

    the_setting_0_pauses_nothing = function()
        local state = build_active_state()
        expect.equal(profile_pause.is_due_at_start(state, read_after_login(0), 0), false)
    end,

    a_start_without_an_active_profile_pauses_nothing = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        expect.equal(profile_pause.is_due_at_start(state, read_after_login(60), 300), false)
    end,

    a_start_that_finds_a_pause_enters_no_new_one = function()
        local paused = profile_state.with_active_profile_paused(build_active_state())
        expect.equal(profile_pause.is_due_at_start(paused, read_after_login(60), 300), false)
    end,

    only_the_first_start_after_a_login_pauses = function()
        local seen = profile_state.with_last_seen_login_time(build_active_state(), LOGIN_TIME)
        expect.equal(profile_pause.is_due_at_start(seen, read_after_login(60), 300), false)
        local never_seen = profile_state.with_last_seen_login_time(build_active_state(), nil)
        expect.equal(profile_pause.is_due_at_start(never_seen, read_after_login(60), 300), true)
    end,

    a_new_login_under_a_start_of_macos_that_the_state_saw_pauses = function()
        local state =
            profile_state.with_last_seen_macos_start_time(build_active_state(), MACOS_START_TIME)
        expect.equal(profile_pause.is_due_at_start(state, read_after_login(60), 300), true)
    end,

    a_start_without_a_login_counts_from_the_start_of_macos = function()
        local state =
            profile_state.with_last_seen_macos_start_time(build_active_state(), MACOS_START_TIME)
        local seen = read_without_login(MACOS_START_TIME, 60)
        expect.equal(profile_pause.is_due_at_start(state, seen, 300), false)
        local new = read_without_login(MACOS_START_TIME + 86400, 60)
        expect.equal(profile_pause.is_due_at_start(state, new, 300), true)
        local late = read_without_login(MACOS_START_TIME + 86400, 300)
        expect.equal(profile_pause.is_due_at_start(state, late, 300), false)
    end,

    a_start_of_macos_that_could_not_be_read_counts_as_a_new_one = function()
        local state = build_active_state()
        expect.equal(profile_pause.is_due_at_start(state, read_without_login(nil, 60), 300), true)
        local unread = profile_state.with_last_seen_macos_start_time(state, nil)
        expect.equal(profile_pause.is_due_at_start(unread, read_without_login(nil, 60), 300), true)
    end,

    the_start_of_macos_is_read_from_the_output_of_sysctl = function()
        expect.equal(
            profile_pause.parse_macos_start_time(
                "{ sec = 1729500000, usec = 829196 } Mon Oct 21 10:40:00 2024\n"
            ),
            MACOS_START_TIME
        )
        expect.equal(profile_pause.parse_macos_start_time(""), nil)
        expect.equal(profile_pause.parse_macos_start_time(nil), nil)
    end,

    the_login_is_read_from_the_console_line_of_the_user = function()
        local reading_time = os.time({ year = 2026, month = 10, day = 4, hour = 21, min = 1 })
        local login = profile_pause.parse_login(
            "jane\n"
                .. reading_time
                .. "\nalex             console      Oct  4 21:00 \n"
                .. "jane             ttys011      Oct  4 21:00 \n"
                .. "jane             console      Oct  4 20:59 \n"
        )
        expect.equal(login, { time = reading_time - 120, seconds_since = 120 })
    end,

    of_two_console_lines_of_the_user_the_latest_login_is_read = function()
        local reading_time = os.time({ year = 2027, month = 1, day = 15, hour = 12, min = 0 })
        local login = profile_pause.parse_login(
            "jane\n"
                .. reading_time
                .. "\njane             console      Jan  2 10:00 \n"
                .. "jane             console      Jan 14 09:30 \n"
        )
        local latest_time = os.time({ year = 2027, month = 1, day = 14, hour = 9, min = 30 })
        expect.equal(login, { time = latest_time, seconds_since = reading_time - latest_time })
    end,

    a_login_dated_after_the_reading_lies_in_the_year_before = function()
        local reading_time =
            os.time({ year = 2027, month = 1, day = 1, hour = 0, min = 0, sec = 30 })
        local login = profile_pause.parse_login(
            "jane\n" .. reading_time .. "\njane             console      Dec 31 23:59 \n"
        )
        expect.equal(login, { time = reading_time - 90, seconds_since = 90 })
    end,

    an_output_without_a_console_line_of_the_user_gives_no_login = function()
        expect.equal(profile_pause.parse_login(nil), nil)
        expect.equal(profile_pause.parse_login(""), nil)
        expect.equal(profile_pause.parse_login("jane\nnot a time\n"), nil)
        expect.equal(
            profile_pause.parse_login(
                "jane\n1791162000\nalex             console      Oct  4 20:59 \n"
            ),
            nil
        )
    end,

    the_lines_name_the_profile_and_the_seconds = function()
        expect.equal(
            profile_pause.describe_start_pause(2, read_after_login(42), 300),
            "profile 2 is paused, because Hammerspoon started 42 seconds after the login, less"
                .. " than pause_after_login_seconds of 300, and activating profile 2"
                .. " restores its layout"
        )
        expect.equal(
            profile_pause.describe_start_pause(2, read_without_login(nil, 42.4), 300),
            "profile 2 is paused, because Hammerspoon started 42 seconds after macOS, less than"
                .. " pause_after_login_seconds of 300, and activating profile 2 restores"
                .. " its layout"
        )
        expect.equal(
            profile_pause.describe_kept_pause(2),
            "profile 2 stays paused, as the state file says, and activating profile 2 restores"
                .. " its layout"
        )
    end,
}
