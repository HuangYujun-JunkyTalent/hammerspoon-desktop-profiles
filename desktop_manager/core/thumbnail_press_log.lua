---The texts that describe a press on the thumbnail of a desktop in Mission Control, from the record
---of the press: the log line of the press, the errors of its presses in the warning when its
---desktop did not show, and the count of its openings and presses in the failure that the press
---reports to the alert after a switch, a restore or a press of the list or the search.
local thumbnail_press_log = {}

---The focus of a window of the application of the chosen window before a press, so that the
---application is the frontmost application when the press ends.
---@class PressFocus
---@field window_description string such as 'Code window "future-work.tex"'
---@field waited_seconds number the seconds from the focus to the end of the wait
---@field frontmost_after number|nil the seconds from the focus until the application was the
---frontmost application, or nil when it was not at the end of the wait

---What happened after the first press on a thumbnail, in seconds since that press.
---@class ThumbnailPress
---@field focus PressFocus|nil the focus before the press, or nil when the press needed none
---@field active_after number|nil when macOS first reported the desktop
---@field closed_after number|nil when the group of the display had gone with the desktop active
---@field is_closed_by_toggle boolean|nil whether the group still showed at the end of the wait
---@field second_press_after number|nil when the desktop manager checked for a second press
---@field is_second_press_made boolean whether a second press on the thumbnail was made
---@field is_closed_at_second_check boolean|nil whether the group of the display had closed at the
---second check
---@field is_opened_again boolean whether Mission Control opened a second time, because the group of
---the display had closed at the second check and the desktop was still not active
---@field second_opening_press_after number|nil when the press of the second opening was made
---@field second_press_error string|nil the error of the second press, the error of the read of the
---desktops at the second check, why the second check found no thumbnail while the group of the
---screen showed, or why the second opening failed

---@param focus PressFocus|nil
---@return string such as 'Code window "future-work.tex" focused before the press, frontmost after
---0.10 seconds'
function thumbnail_press_log.describe_focus(focus)
    if not focus then
        return "no focus before the press"
    end
    if focus.frontmost_after then
        return string.format(
            "%s focused before the press, frontmost after %.2f seconds",
            focus.window_description,
            focus.frontmost_after
        )
    end
    return string.format(
        "%s focused before the press, not frontmost after %.2f seconds",
        focus.window_description,
        focus.waited_seconds
    )
end

---@param press ThumbnailPress
---@return string such as "a second press after 2.00 seconds"
local function describe_second_check(press)
    local failure = press.second_press_error and (", which failed: " .. press.second_press_error)
        or ""
    if not press.second_press_after then
        return "one press"
    end
    if press.is_opened_again then
        local pressed = press.second_opening_press_after
                and string.format(
                    " and a second press after %.2f seconds",
                    press.second_opening_press_after
                )
            or ""
        return string.format("a second opening after %.2f seconds", press.second_press_after)
            .. pressed
            .. failure
    end
    if press.is_second_press_made then
        return string.format("a second press after %.2f seconds", press.second_press_after)
            .. failure
    end
    return string.format(
        "no second press after %.2f seconds, because %s",
        press.second_press_after,
        press.second_press_error or "Mission Control had closed"
    )
end

---@param press ThumbnailPress
---@param waited_seconds number
---@return string such as "no focus before the press, active after 0.84 seconds, Mission Control
---closed after 0.90 seconds, one press"
function thumbnail_press_log.describe_press(press, waited_seconds)
    local parts = { thumbnail_press_log.describe_focus(press.focus) }
    if press.active_after then
        table.insert(parts, string.format("active after %.2f seconds", press.active_after))
    else
        table.insert(parts, string.format("not active after %.2f seconds", waited_seconds))
    end
    if press.closed_after then
        table.insert(
            parts,
            string.format("Mission Control closed after %.2f seconds", press.closed_after)
        )
    elseif press.is_closed_by_toggle then
        table.insert(
            parts,
            string.format(
                "Mission Control still showed after %.2f seconds and closed by a toggle",
                waited_seconds
            )
        )
    else
        table.insert(
            parts,
            string.format("Mission Control had closed by %.2f seconds", waited_seconds)
        )
    end
    table.insert(parts, describe_second_check(press))
    return table.concat(parts, ", ")
end

---@param press ThumbnailPress
---@return string the error of each press, such as "The second press failed: ..."
function thumbnail_press_log.describe_press_errors(press)
    if not press.second_press_error then
        return "No press failed."
    end
    if press.is_second_press_made then
        return string.format("The second press failed: %s.", press.second_press_error)
    end
    return string.format("At the second check, %s.", press.second_press_error)
end

---@param press ThumbnailPress
---@return string such as "one opening and two presses"
function thumbnail_press_log.count_openings_and_presses(press)
    if press.is_opened_again then
        return "two openings and two presses"
    end
    if press.is_second_press_made then
        return "one opening and two presses"
    end
    return "one opening and one press"
end

return thumbnail_press_log
