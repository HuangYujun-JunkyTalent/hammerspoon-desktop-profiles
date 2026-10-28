local expect = require("tests.expect")
local thumbnail_press_log = require("desktop_manager.core.thumbnail_press_log")

local FOCUS_DESCRIPTION = 'Code window "future-work.tex"'

---@param fields table the fields of the press beside the defaults of a press without a focus
---@return ThumbnailPress
local function make_press(fields)
    local press = { is_second_press_made = false, is_opened_again = false }
    for key, value in pairs(fields) do
        press[key] = value
    end
    return press
end

return {
    the_focus_reads_as_none_or_names_the_window_and_when_its_application_was_frontmost = function()
        expect.equal(thumbnail_press_log.describe_focus(nil), "no focus before the press")
        expect.equal(
            thumbnail_press_log.describe_focus({
                window_description = FOCUS_DESCRIPTION,
                waited_seconds = 0.1,
                frontmost_after = 0.1,
            }),
            FOCUS_DESCRIPTION .. " focused before the press, frontmost after 0.10 seconds"
        )
        expect.equal(
            thumbnail_press_log.describe_focus({
                window_description = FOCUS_DESCRIPTION,
                waited_seconds = 1,
            }),
            FOCUS_DESCRIPTION .. " focused before the press, not frontmost after 1.00 seconds"
        )
    end,

    a_press_that_showed_its_desktop_reads_as_active_closed_and_one_press = function()
        local press = make_press({ active_after = 0.84, closed_after = 0.9 })
        expect.equal(
            thumbnail_press_log.describe_press(press, 0.9),
            "no focus before the press, active after 0.84 seconds,"
                .. " Mission Control closed after 0.90 seconds, one press"
        )
        expect.equal(thumbnail_press_log.describe_press_errors(press), "No press failed.")
        expect.equal(
            thumbnail_press_log.count_openings_and_presses(press),
            "one opening and one press"
        )
    end,

    a_failed_second_press_reads_with_its_error_after_a_toggle = function()
        local press = make_press({
            is_closed_by_toggle = true,
            second_press_after = 2,
            is_second_press_made = true,
            second_press_error = "Mission Control rejected AXPress: the element is gone",
        })
        expect.equal(
            thumbnail_press_log.describe_press(press, 5.05),
            "no focus before the press, not active after 5.05 seconds,"
                .. " Mission Control still showed after 5.05 seconds and closed by a toggle,"
                .. " a second press after 2.00 seconds,"
                .. " which failed: Mission Control rejected AXPress: the element is gone"
        )
        expect.equal(
            thumbnail_press_log.describe_press_errors(press),
            "The second press failed: Mission Control rejected AXPress: the element is gone."
        )
        expect.equal(
            thumbnail_press_log.count_openings_and_presses(press),
            "one opening and two presses"
        )
    end,

    a_second_check_without_a_press_reads_with_its_reason = function()
        local closed = make_press({ second_press_after = 2, is_closed_at_second_check = true })
        expect.equal(
            thumbnail_press_log.describe_press(closed, 5),
            "no focus before the press, not active after 5.00 seconds,"
                .. " Mission Control had closed by 5.00 seconds,"
                .. " no second press after 2.00 seconds, because Mission Control had closed"
        )
        local unread = make_press({
            second_press_after = 2,
            second_press_error = "reading the desktops failed: no displays",
        })
        expect.equal(
            thumbnail_press_log.describe_press(unread, 5),
            "no focus before the press, not active after 5.00 seconds,"
                .. " Mission Control had closed by 5.00 seconds,"
                .. " no second press after 2.00 seconds,"
                .. " because reading the desktops failed: no displays"
        )
        expect.equal(
            thumbnail_press_log.describe_press_errors(unread),
            "At the second check, reading the desktops failed: no displays."
        )
        expect.equal(
            thumbnail_press_log.count_openings_and_presses(unread),
            "one opening and one press"
        )
    end,

    a_second_opening_reads_with_its_press_or_its_failure = function()
        local pressed = make_press({
            focus = {
                window_description = FOCUS_DESCRIPTION,
                waited_seconds = 0,
                frontmost_after = 0,
            },
            active_after = 3.45,
            closed_after = 3.45,
            second_press_after = 2,
            is_opened_again = true,
            is_second_press_made = true,
            second_opening_press_after = 2.4,
        })
        expect.equal(
            thumbnail_press_log.describe_press(pressed, 3.45),
            FOCUS_DESCRIPTION
                .. " focused before the press, frontmost after 0.00 seconds,"
                .. " active after 3.45 seconds, Mission Control closed after 3.45 seconds,"
                .. " a second opening after 2.00 seconds and a second press after 2.40 seconds"
        )
        expect.equal(
            thumbnail_press_log.count_openings_and_presses(pressed),
            "two openings and two presses"
        )
        local failed = make_press({
            second_press_after = 2,
            is_opened_again = true,
            second_press_error = "Mission Control showed no group for display 2",
        })
        expect.equal(
            thumbnail_press_log.describe_press(failed, 2.8),
            "no focus before the press, not active after 2.80 seconds,"
                .. " Mission Control had closed by 2.80 seconds,"
                .. " a second opening after 2.00 seconds,"
                .. " which failed: Mission Control showed no group for display 2"
        )
    end,

    a_block_of_half_a_second_or_more_reads_in_the_log_line = function()
        local blocked = make_press({ active_after = 2.1, closed_after = 2.1 })
        blocked.longest_block_seconds = 1.5
        expect.equal(
            thumbnail_press_log.describe_press(blocked, 2.1),
            "no focus before the press, active after 2.10 seconds,"
                .. " Mission Control closed after 2.10 seconds, one press,"
                .. " Hammerspoon was blocked for up to 1.50 seconds between two checks"
        )
        blocked.longest_block_seconds = 0.4
        expect.equal(thumbnail_press_log.describe_press(blocked, 2.1):find("blocked"), nil)
    end,
}
