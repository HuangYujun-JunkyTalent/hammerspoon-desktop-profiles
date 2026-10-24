local expect = require("tests.expect")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local profile_pause = require("desktop_manager.core.profile_pause")
local profile_state = require("desktop_manager.core.profile_state")

local MACOS_START_TIME = 1729500000
local EARLIER_MACOS_START_TIME = 1729400000

---@return State a state in which profile 1 is active, saved under an earlier start of macOS
local function build_active_state()
    return profile_state.with_last_seen_macos_start_time(
        profile_state.with_active_profile_number(
            profile_state.new_state(monitor_matching.BY_COUNT),
            1
        ),
        EARLIER_MACOS_START_TIME
    )
end

return {
    a_start_before_the_setting_pauses_the_active_profile = function()
        local state = build_active_state()
        expect.equal(profile_pause.is_due_at_start(state, MACOS_START_TIME, 60, 300), true)
        expect.equal(profile_pause.is_due_at_start(state, MACOS_START_TIME, 299.9, 300), true)
    end,

    a_start_at_or_after_the_setting_pauses_nothing = function()
        local state = build_active_state()
        expect.equal(profile_pause.is_due_at_start(state, MACOS_START_TIME, 300, 300), false)
        expect.equal(profile_pause.is_due_at_start(state, MACOS_START_TIME, 3600, 300), false)
    end,

    the_setting_0_pauses_nothing = function()
        local state = build_active_state()
        expect.equal(profile_pause.is_due_at_start(state, MACOS_START_TIME, 0, 0), false)
    end,

    a_start_without_an_active_profile_pauses_nothing = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        expect.equal(profile_pause.is_due_at_start(state, MACOS_START_TIME, 60, 300), false)
    end,

    a_start_that_finds_a_pause_enters_no_new_one = function()
        local paused = profile_state.with_active_profile_paused(build_active_state())
        expect.equal(profile_pause.is_due_at_start(paused, MACOS_START_TIME, 60, 300), false)
    end,

    only_the_first_start_after_a_start_of_macos_pauses = function()
        local seen =
            profile_state.with_last_seen_macos_start_time(build_active_state(), MACOS_START_TIME)
        expect.equal(profile_pause.is_due_at_start(seen, MACOS_START_TIME, 60, 300), false)
        local never_seen = profile_state.with_last_seen_macos_start_time(build_active_state(), nil)
        expect.equal(profile_pause.is_due_at_start(never_seen, MACOS_START_TIME, 60, 300), true)
    end,

    a_start_of_macos_that_could_not_be_read_counts_as_a_new_one = function()
        local state = build_active_state()
        expect.equal(profile_pause.is_due_at_start(state, nil, 60, 300), true)
        local unread = profile_state.with_last_seen_macos_start_time(state, nil)
        expect.equal(profile_pause.is_due_at_start(unread, nil, 60, 300), true)
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
            profile_pause.describe_start_pause(2, 42.4, 300),
            "profile 2 is paused, because Hammerspoon started 42 seconds after macOS, less than"
                .. " pause_after_macos_start_seconds of 300, and activating profile 2 restores"
                .. " its layout"
        )
        expect.equal(
            profile_pause.describe_kept_pause(2),
            "profile 2 stays paused, as the state file says, and activating profile 2 restores"
                .. " its layout"
        )
    end,
}
