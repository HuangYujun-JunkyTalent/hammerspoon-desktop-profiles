---Shows, adds and removes desktops by pressing the elements of Mission Control through
---accessibility, and is the one module of the desktop manager that opens Mission Control.
---macOS 27 keeps the accessibility tree of Mission Control under the process WindowManager, where
---Hammerspoon 1.1.1 still looks under the Dock.
---https://github.com/Hammerspoon/hammerspoon/issues/3897 reports the move.
---The identifiers `mc.display`, `mc.spaces.add` and `mc.spaces.list` and the actions `AXPress` and
---`AXRemoveDesktop` are those that `hs.spaces` of Hammerspoon 1.1.1 uses with the Dock.
---A press on the thumbnail of a desktop shows the desktop and closes Mission Control, as in
---`hs.spaces.gotoSpace`, so one opening holds every addition and removal and the press on at most
---one desktop, at its end, pressed a second time when the first press has not shown it in time.
---A press for a chosen window may first focus another window of its application, and a press whose
---desktop is still inactive after Mission Control closed opens Mission Control a second time.
local focus_before_press = require("desktop_manager.macos.focus_before_press")
local keyboard_modifiers = require("desktop_manager.macos.keyboard_modifiers")
local poll_until = require("desktop_manager.macos.poll_until")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local retained_timers = require("desktop_manager.macos.retained_timers")
local track_windows = require("desktop_manager.macos.track_windows")

local mission_control_desktops = {}

---The desktops to add to one screen and to remove from it, in one opening of Mission Control.
---@class DesktopEdit
---@field screen_uuid string
---@field slot_key string the name of the screen in the messages, such as "built-in"
---@field desktops_to_add integer
---@field space_ids_to_remove integer[]

local MISSION_CONTROL_OWNER_BUNDLE_ID = "com.apple.WindowManager"
local DISPLAY_SEARCH_DEPTH = 6
local BUTTON_SEARCH_DEPTH = 4
local MISSION_CONTROL_POLL_SECONDS = 0.1

local log = nil

---The number of calls of `stop_openings`, which a callback of an opening compares with the number
---at the time the callback was made.
local stopped_count = 0

---Wraps a callback of the opening that runs, so that the callback does nothing once
---`stop_openings` has stopped that opening.
---@param callback function
---@return function
local function continue_opening(callback)
    local stopped_before = stopped_count
    return function(...)
        if stopped_before == stopped_count then
            callback(...)
        end
    end
end

---Calls `on_done(true)` once `is_met` returns true, or `on_done(false)` after the timeout, as
---`poll_until.wait` does, and ends the wait without a call once `stop_openings` has stopped the
---opening that runs.
---@param is_met fun(): boolean
---@param timeout_seconds number
---@param interval_seconds number
---@param on_done fun(is_met: boolean)
local function wait_while_opening(is_met, timeout_seconds, interval_seconds, on_done)
    local stopped_before = stopped_count
    local function is_stopped()
        return stopped_before ~= stopped_count
    end
    poll_until.wait(
        function()
            return is_stopped() or is_met()
        end,
        timeout_seconds,
        interval_seconds,
        function(has_met)
            if not is_stopped() then
                on_done(has_met)
            end
        end
    )
end

---@return table an hs.logger, made at the first opening, because the tests load this module
---without Hammerspoon
local function get_log()
    log = log or hs.logger.new("mission_ctl", "info")
    return log
end

---@param element table an hs.axuielement
---@param attribute string
---@return any
local function read_attribute(element, attribute)
    local is_successful, value = pcall(element.attributeValue, element, attribute)
    return is_successful and value or nil
end

---Depth-first search of the accessibility tree below `element`.
---@param element table an hs.axuielement
---@param is_wanted fun(element: table): boolean
---@param depth_left integer
---@return table|nil
local function find_descendant(element, is_wanted, depth_left)
    if depth_left <= 0 then
        return nil
    end
    for _, child in ipairs(read_attribute(element, "AXChildren") or {}) do
        if is_wanted(child) then
            return child
        end
        local found = find_descendant(child, is_wanted, depth_left - 1)
        if found then
            return found
        end
    end
    return nil
end

---@param identifier string
---@return fun(element: table): boolean
local function has_identifier(identifier)
    return function(element)
        return read_attribute(element, "AXIdentifier") == identifier
    end
end

---@param screen_id integer the `hs.screen:id()` of the display
---@return table|nil display_group the `mc.display` element, present while Mission Control shows
local function find_display_group(screen_id)
    local application = track_windows.find_running_application(MISSION_CONTROL_OWNER_BUNDLE_ID)
    if not application then
        return nil
    end
    local is_display_group = has_identifier("mc.display")
    return find_descendant(hs.axuielement.applicationElement(application), function(element)
        return is_display_group(element) and read_attribute(element, "AXDisplayID") == screen_id
    end, DISPLAY_SEARCH_DEPTH)
end

---@param element table an hs.axuielement
---@param action string
---@return string|nil error_message
local function perform(element, action)
    local is_successful, result, error_message = pcall(element.performAction, element, action)
    if not is_successful then
        return tostring(result)
    end
    if not result then
        return string.format("Mission Control rejected %s: %s", action, tostring(error_message))
    end
    return nil
end

---@param space_ids integer[]
---@param space_id integer
---@return integer|nil the position of the desktop in the list
local function find_position(space_ids, space_id)
    for position, candidate in ipairs(space_ids) do
        if candidate == space_id then
            return position
        end
    end
    return nil
end

---The thumbnail of the desktop in the list of the desktops of its screen in Mission Control.
---The position of the thumbnail is the position of the desktop among every space of its screen,
---full-screen ones included, as in `hs.spaces.gotoSpace`.
---@param spaces_list table|nil the `mc.spaces.list` element of the screen, or nil when it did not
---show
---@param screen_uuid string
---@param space_id integer
---@return table|nil thumbnail an hs.axuielement
---@return integer|nil position
local function find_listed_thumbnail(spaces_list, screen_uuid, space_id)
    local position =
        find_position(read_desktops.list_all_space_ids_of_screen(screen_uuid), space_id)
    local thumbnail = spaces_list
        and position
        and (read_attribute(spaces_list, "AXChildren") or {})[position]
    return thumbnail, position
end

---@param space_id integer
---@return string such as "desktop 2 of Built-in Retina Display"
local function describe_desktop(space_id)
    local screen_uuid = read_desktops.find_screen_uuid_of_any_space(space_id)
    if not screen_uuid then
        return string.format("desktop %d", space_id)
    end
    local screen = read_screens.find_screen(screen_uuid)
    local screen_name = screen and screen:name() or screen_uuid
    local screen_desktops = read_desktops.find_screen_of_space(space_id)
    if not screen_desktops then
        return string.format("the space in full screen %d of %s", space_id, screen_name)
    end
    return string.format(
        "desktop %d of %s",
        find_position(screen_desktops.space_ids, space_id),
        screen_name
    )
end

---Closes Mission Control by a toggle while the group of the display shows.
---@param screen_id integer
---@param timing Timing
---@param on_closed fun()
---@return boolean is_toggled whether the group showed, so that the toggle closed Mission Control
local function close_mission_control(screen_id, timing, on_closed)
    local is_toggled = find_display_group(screen_id) ~= nil
    if is_toggled then
        hs.spaces.toggleMissionControl()
    end
    retained_timers.after(timing.mission_control_press_gap_seconds, continue_opening(on_closed))
    return is_toggled
end

---Opens Mission Control once the user has released the modifier keys, and calls `on_open` once the
---group of the display shows.
---Option held in Mission Control turns the thumbnails into buttons that remove desktops, so
---Mission Control stays closed while a modifier key is held.
---@param screen_id integer
---@param timing Timing
---@param on_open fun()
---@param on_failure fun(error_message: string)
local function open_mission_control(screen_id, timing, on_open, on_failure)
    local requested_at = hs.timer.secondsSinceEpoch()
    keyboard_modifiers.wait_for_release(
        timing,
        continue_opening(function(are_released)
            if not are_released then
                on_failure(
                    string.format(
                        "Release the modifier keys: Mission Control stays closed"
                            .. " while they are held, and they were held for %g seconds",
                        timing.modifier_release_timeout_seconds
                    )
                )
                return
            end
            local released_at = hs.timer.secondsSinceEpoch()
            local was_open = find_display_group(screen_id) ~= nil
            if not was_open then
                hs.spaces.toggleMissionControl()
            end
            poll_until.wait(
                function()
                    return find_display_group(screen_id) ~= nil
                end,
                timing.mission_control_timeout_seconds,
                MISSION_CONTROL_POLL_SECONDS,
                continue_opening(function(is_shown)
                    get_log().f(
                        "%.2f seconds for the release of the modifiers,"
                            .. " %.2f seconds until Mission Control showed",
                        released_at - requested_at,
                        hs.timer.secondsSinceEpoch() - released_at
                    )
                    if not is_shown then
                        if not was_open then
                            hs.spaces.toggleMissionControl()
                        end
                        on_failure(
                            string.format(
                                "Mission Control showed no group for display %d",
                                screen_id
                            )
                        )
                        return
                    end
                    retained_timers.after(
                        timing.mission_control_press_gap_seconds,
                        continue_opening(on_open)
                    )
                end)
            )
        end)
    )
end

---@param display_group table
---@param edit DesktopEdit
---@param timing Timing
---@param failures string[]
---@param on_done fun()
local function add_desktops(display_group, edit, timing, failures, on_done)
    if edit.desktops_to_add == 0 then
        on_done()
        return
    end
    local add_button =
        find_descendant(display_group, has_identifier("mc.spaces.add"), BUTTON_SEARCH_DEPTH)
    if not add_button then
        table.insert(
            failures,
            string.format("Mission Control showed no button to add a desktop to %s", edit.slot_key)
        )
        on_done()
        return
    end
    local remaining = edit.desktops_to_add
    local function press_next()
        if remaining == 0 then
            on_done()
            return
        end
        remaining = remaining - 1
        local error_message = perform(add_button, "AXPress")
        if error_message then
            table.insert(
                failures,
                string.format("Adding desktops to %s failed: %s", edit.slot_key, error_message)
            )
            on_done()
            return
        end
        retained_timers.after(
            timing.mission_control_press_gap_seconds,
            continue_opening(press_next)
        )
    end
    press_next()
end

---Checks a desktop again right before its removal, because the user may have shown it or moved a
---window onto it since the plan.
---@param space_id integer
---@param find_keeping_window fun(window_ids: integer[]): integer|nil
---@return string|nil reason why the desktop stays
local function find_reason_to_keep(space_id, find_keeping_window)
    if read_desktops.is_space_active(space_id) then
        return "it shows"
    end
    local is_listed, window_ids = pcall(hs.spaces.windowsForSpace, space_id)
    if not is_listed or type(window_ids) ~= "table" then
        return "macOS did not list its windows"
    end
    local keeping_window_id = find_keeping_window(window_ids)
    if keeping_window_id then
        return string.format("window %s is on it", tostring(keeping_window_id))
    end
    return nil
end

---Removes the desktops of the edit from the end of the screen, and reads the positions of the
---thumbnails again before each removal.
---@param display_group table
---@param edit DesktopEdit
---@param find_keeping_window fun(window_ids: integer[]): integer|nil
---@param timing Timing
---@param failures string[]
---@param on_done fun()
local function remove_desktops(display_group, edit, find_keeping_window, timing, failures, on_done)
    if #edit.space_ids_to_remove == 0 then
        on_done()
        return
    end
    local spaces_list =
        find_descendant(display_group, has_identifier("mc.spaces.list"), BUTTON_SEARCH_DEPTH)
    if not spaces_list then
        table.insert(
            failures,
            string.format("Mission Control showed no list of the desktops of %s", edit.slot_key)
        )
        on_done()
        return
    end
    local space_ids_from_the_end = {}
    for _, space_id in ipairs(read_desktops.list_all_space_ids_of_screen(edit.screen_uuid)) do
        if find_position(edit.space_ids_to_remove, space_id) then
            table.insert(space_ids_from_the_end, 1, space_id)
        end
    end
    local next_index = 1
    local function remove_next()
        local space_id = space_ids_from_the_end[next_index]
        if space_id == nil then
            on_done()
            return
        end
        next_index = next_index + 1
        local reason = find_reason_to_keep(space_id, find_keeping_window)
        if reason then
            get_log().f("desktop %d of %s stays, because %s", space_id, edit.slot_key, reason)
            remove_next()
            return
        end
        local thumbnail, position = find_listed_thumbnail(spaces_list, edit.screen_uuid, space_id)
        if not thumbnail then
            table.insert(
                failures,
                string.format(
                    "Mission Control listed no desktop at position %s of %s",
                    tostring(position),
                    edit.slot_key
                )
            )
            on_done()
            return
        end
        local error_message = perform(thumbnail, "AXRemoveDesktop")
        if error_message then
            table.insert(
                failures,
                string.format("Removing a desktop of %s failed: %s", edit.slot_key, error_message)
            )
            on_done()
            return
        end
        retained_timers.after(
            timing.mission_control_press_gap_seconds,
            continue_opening(remove_next)
        )
    end
    remove_next()
end

---@param edits DesktopEdit[]
---@param find_keeping_window fun(window_ids: integer[]): integer|nil
---@param timing Timing
---@param failures string[]
---@param on_done fun()
local function apply_edits(edits, find_keeping_window, timing, failures, on_done)
    local next_index = 1
    local function apply_next()
        local edit = edits[next_index]
        if edit == nil then
            on_done()
            return
        end
        next_index = next_index + 1
        local screen = read_screens.find_screen(edit.screen_uuid)
        local display_group = screen and find_display_group(screen:id())
        if not display_group then
            table.insert(
                failures,
                string.format("Mission Control showed no group for %s", edit.slot_key)
            )
            apply_next()
            return
        end
        add_desktops(display_group, edit, timing, failures, function()
            remove_desktops(display_group, edit, find_keeping_window, timing, failures, apply_next)
        end)
    end
    apply_next()
end

---The thumbnail of the desktop in the list of its screen in Mission Control, read anew at each
---call, because an element read before a press may no longer stand for the thumbnail.
---@param space_id integer
---@param screen_uuid string|nil the screen whose spaces hold the desktop
---@return table|nil thumbnail an hs.axuielement
---@return integer|nil position
---@return boolean is_group_shown whether the group of the screen showed in Mission Control
local function find_thumbnail(space_id, screen_uuid)
    if not screen_uuid then
        return nil, nil, false
    end
    local screen = read_screens.find_screen(screen_uuid)
    local display_group = screen and find_display_group(screen:id())
    local spaces_list = display_group
        and find_descendant(display_group, has_identifier("mc.spaces.list"), BUTTON_SEARCH_DEPTH)
    local thumbnail, position = find_listed_thumbnail(spaces_list, screen_uuid, space_id)
    return thumbnail, position, display_group ~= nil
end

---Finds the thumbnail anew for the second press, in the same opening or in the second opening, as
---`find_thumbnail` does, and gives the text of the failure when the read of the desktops fails or
---Mission Control lists no thumbnail at the position of the desktop.
---@param space_id integer
---@param screen_uuid string|nil the screen whose spaces hold the desktop
---@return table|nil thumbnail an hs.axuielement
---@return string|nil failure the text of the failure when no thumbnail was found
---@return boolean|nil is_group_shown whether the group of the screen showed in Mission Control, or
---nil when the read of the desktops failed
local function find_thumbnail_for_second_press(space_id, screen_uuid)
    local is_read, thumbnail, position, is_group_shown =
        pcall(find_thumbnail, space_id, screen_uuid)
    if not is_read then
        return nil, string.format("reading the desktops failed: %s", tostring(thumbnail)), nil
    end
    if not thumbnail then
        return nil,
            string.format("Mission Control listed no thumbnail at position %s", tostring(position)),
            is_group_shown
    end
    return thumbnail, nil, is_group_shown
end

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

---A failed read counts as a desktop not yet active, so that the press goes on polling.
---@param space_id integer
---@return boolean whether macOS reported the desktop as active
local function is_space_active_safely(space_id)
    local is_read, is_active = pcall(read_desktops.is_space_active, space_id)
    return is_read and is_active == true
end

---@param focus PressFocus|nil
---@return string such as 'Code window "future-work.tex" focused before the press, frontmost after
---0.10 seconds'
local function describe_focus(focus)
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

---Writes the focus before the press and the failure of a press that ends before its first press on
---the thumbnail, so that the console names every focus that ran.
---A press without a focus writes nothing, as the alert names the failure.
---@param description string the desktop of the press, such as "desktop 2 of DELL S2725DS"
---@param focus PressFocus|nil
---@param failure string
local function log_failure_after_focus(description, focus, failure)
    if focus then
        get_log().f("%s: %s. %s", description, describe_focus(focus), failure)
    end
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
local function describe_press(press, waited_seconds)
    local parts = { describe_focus(press.focus) }
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
local function describe_press_errors(press)
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
local function count_openings_and_presses(press)
    if press.is_opened_again then
        return "two openings and two presses"
    end
    if press.is_second_press_made then
        return "one opening and two presses"
    end
    return "one opening and one press"
end

---Presses the thumbnail of the desktop, which shows it and closes Mission Control, and waits up
---to `desktop_show_timeout_seconds` after the last press until macOS reports the desktop and
---Mission Control has closed.
---When the desktop is not active `desktop_press_retry_seconds` after the first press and Mission
---Control still shows, the thumbnail is found again and pressed a second time, because Mission
---Control may ignore a press, and a toggle would undo a press that is still taking effect.
---When the desktop is not active at that check and Mission Control has closed, Mission Control
---opens a second time on the same display and the thumbnail is found again and pressed, because
---macOS may show the desktop that the press replaced again after Mission Control closed.
---No third press or opening follows.
---Until the desktop is active, each poll reads the active desktops alone, and the accessibility
---tree of WindowManager is read only at the second check, in the second opening and at the end of
---the wait.
---@param space_id integer
---@param screen_id integer the display whose group showed at the opening
---@param timing Timing
---@param focus PressFocus|nil the focus before the press
---@param on_done fun(error_message: string|nil)
local function press_thumbnail(space_id, screen_id, timing, focus, on_done)
    local description = describe_desktop(space_id)
    local screen_uuid = read_desktops.find_screen_uuid_of_any_space(space_id)
    local thumbnail, position = find_thumbnail(space_id, screen_uuid)
    ---@param failure string
    local function fail_first_press(failure)
        close_mission_control(screen_id, timing, function()
            log_failure_after_focus(description, focus, failure)
            on_done(failure)
        end)
    end
    if not thumbnail then
        fail_first_press(
            string.format(
                "Mission Control listed no thumbnail of %s at position %s",
                description,
                tostring(position)
            )
        )
        return
    end
    local error_message = perform(thumbnail, "AXPress")
    if error_message then
        fail_first_press(string.format("Showing %s failed: %s", description, error_message))
        return
    end
    local pressed_at = hs.timer.secondsSinceEpoch()
    local last_pressed_at = pressed_at
    ---@type ThumbnailPress
    local press = { focus = focus, is_second_press_made = false, is_opened_again = false }

    ---@param waited_seconds number
    local function press_again(waited_seconds)
        press.second_press_after = waited_seconds
        local second_thumbnail, failure, is_group_shown =
            find_thumbnail_for_second_press(space_id, screen_uuid)
        if is_group_shown == false then
            press.is_closed_at_second_check = true
            return
        end
        if not second_thumbnail then
            press.second_press_error = failure
            return
        end
        press.is_second_press_made = true
        press.second_press_error = perform(second_thumbnail, "AXPress")
    end

    local poll

    ---Ends the press with the failure of the second opening, after the log line of the press.
    ---@param failure string
    local function fail_second_opening(failure)
        press.second_press_error = failure
        get_log().f(
            "%s: %s",
            description,
            describe_press(press, hs.timer.secondsSinceEpoch() - pressed_at)
        )
        on_done(
            string.format(
                "Mission Control did not show %s after one press,"
                    .. " and the second opening failed: %s",
                description,
                failure
            )
        )
    end

    ---Opens Mission Control a second time and presses the thumbnail, found anew, and goes on
    ---polling up to `desktop_show_timeout_seconds` after that press.
    local function open_again()
        press.is_opened_again = true
        open_mission_control(screen_id, timing, function()
            local again_thumbnail, failure = find_thumbnail_for_second_press(space_id, screen_uuid)
            if again_thumbnail then
                failure = perform(again_thumbnail, "AXPress")
            end
            if failure then
                close_mission_control(screen_id, timing, function()
                    fail_second_opening(failure)
                end)
                return
            end
            last_pressed_at = hs.timer.secondsSinceEpoch()
            press.is_second_press_made = true
            press.second_opening_press_after = last_pressed_at - pressed_at
            poll()
        end, fail_second_opening)
    end

    ---@param waited_seconds number
    local function finish_at_deadline(waited_seconds)
        local is_active = is_space_active_safely(space_id)
        press.is_closed_by_toggle = close_mission_control(screen_id, timing, function()
            if is_active then
                retained_timers.after(
                    timing.desktop_settle_seconds,
                    continue_opening(function()
                        on_done(nil)
                    end)
                )
                return
            end
            local is_read, screen_desktops = pcall(read_desktops.find_screen_desktops, screen_uuid)
            local shown_space_id = is_read and screen_desktops and screen_desktops.active_space_id
            get_log().w(
                string.format(
                    "%s did not show. Its screen shows %s, and Mission Control %s at the end of"
                        .. " the wait. %s",
                    description,
                    shown_space_id and describe_desktop(shown_space_id) or "no desktop",
                    press.is_closed_by_toggle and "still showed" or "had closed",
                    describe_press_errors(press)
                )
            )
            on_done(
                string.format(
                    "Mission Control did not show %s within %g seconds, after %s",
                    description,
                    timing.desktop_show_timeout_seconds,
                    count_openings_and_presses(press)
                )
            )
        end)
        get_log().f("%s: %s", description, describe_press(press, waited_seconds))
    end

    poll = function()
        local now = hs.timer.secondsSinceEpoch()
        local waited_seconds = now - pressed_at
        if not press.active_after and is_space_active_safely(space_id) then
            press.active_after = waited_seconds
        end
        if press.active_after and find_display_group(screen_id) == nil then
            press.closed_after = waited_seconds
            get_log().f("%s: %s", description, describe_press(press, waited_seconds))
            retained_timers.after(
                timing.desktop_settle_seconds,
                continue_opening(function()
                    on_done(nil)
                end)
            )
            return
        end
        if now - last_pressed_at >= timing.desktop_show_timeout_seconds then
            finish_at_deadline(waited_seconds)
            return
        end
        if
            not press.active_after
            and not press.second_press_after
            and waited_seconds >= timing.desktop_press_retry_seconds
        then
            press_again(waited_seconds)
            if press.is_closed_at_second_check and not is_space_active_safely(space_id) then
                open_again()
                return
            end
        end
        retained_timers.after(timing.poll_interval_seconds, continue_opening(poll))
    end
    poll()
end

---Focuses the window of the application of the chosen window that `focus_before_press` finds, and
---waits up to `application_focus_timeout_seconds` until the application is the frontmost
---application.
---The press goes on also when the application is not frontmost at the end of the wait.
---@param chosen_window ChosenWindow|nil
---@param space_id integer|nil the desktop that the press shows, which a chosen window needs
---@param timing Timing
---@param on_focused fun(focus: PressFocus|nil)
local function focus_application(chosen_window, space_id, timing, on_focused)
    if not chosen_window then
        on_focused(nil)
        return
    end
    local is_found, window = pcall(focus_before_press.find_window_to_focus, chosen_window, space_id)
    if not is_found then
        get_log().w("Finding the window to focus before the press failed: " .. tostring(window))
    end
    if not is_found or not window then
        on_focused(nil)
        return
    end
    local application = window:application()
    local focus = {
        window_description = string.format(
            "%s window %q",
            application and application:name() or chosen_window.bundle_id,
            window:title() or ""
        ),
        waited_seconds = 0,
    }
    local focused_at = hs.timer.secondsSinceEpoch()
    window:focus()
    wait_while_opening(
        function()
            return focus_before_press.is_frontmost(chosen_window.bundle_id)
        end,
        timing.application_focus_timeout_seconds,
        timing.poll_interval_seconds,
        function(is_frontmost)
            focus.waited_seconds = hs.timer.secondsSinceEpoch() - focused_at
            focus.frontmost_after = is_frontmost and focus.waited_seconds or nil
            on_focused(focus)
        end
    )
end

---@param edits DesktopEdit[]
---@return DesktopEdit[] the edits that add or remove a desktop
local function keep_edits_with_work(edits)
    local kept = {}
    for _, edit in ipairs(edits) do
        if edit.desktops_to_add > 0 or #edit.space_ids_to_remove > 0 then
            table.insert(kept, edit)
        end
    end
    return kept
end

---@param edits DesktopEdit[]
---@param space_id integer|nil
---@return table|nil an hs.screen whose group shows that Mission Control is open
local function find_opening_screen(edits, space_id)
    for _, edit in ipairs(edits) do
        local screen = read_screens.find_screen(edit.screen_uuid)
        if screen then
            return screen
        end
    end
    local screen_uuid = space_id and read_desktops.find_screen_uuid_of_any_space(space_id)
    return screen_uuid and read_screens.find_screen(screen_uuid)
end

---Opens Mission Control once for the edits of every screen and the press at the end.
---@param edits DesktopEdit[]
---@param space_id integer|nil the desktop to show at the end, or nil to close by a toggle
---@param find_keeping_window fun(window_ids: integer[]): integer|nil
---@param timing Timing
---@param chosen_window ChosenWindow|nil the window that the press brings to the front, for the
---focus before the press
---@param on_done fun(failures: string[])
local function run_opening(edits, space_id, find_keeping_window, timing, chosen_window, on_done)
    local edits_with_work = keep_edits_with_work(edits)
    local is_press_needed = space_id ~= nil and not read_desktops.is_space_active(space_id)
    if #edits_with_work == 0 and not is_press_needed then
        on_done({})
        return
    end
    local screen = find_opening_screen(edits_with_work, is_press_needed and space_id or nil)
    if not screen then
        local failures = {}
        for _, edit in ipairs(edits_with_work) do
            table.insert(failures, string.format("%s is gone, so its desktops stay", edit.slot_key))
        end
        if is_press_needed then
            table.insert(failures, string.format("desktop %d is on no screen", space_id))
        end
        on_done(failures)
        return
    end
    local screen_id = screen:id()
    focus_application(chosen_window, space_id, timing, function(focus)
        open_mission_control(screen_id, timing, function()
            local failures = {}
            apply_edits(edits_with_work, find_keeping_window, timing, failures, function()
                if space_id == nil or read_desktops.is_space_active(space_id) then
                    close_mission_control(screen_id, timing, function()
                        on_done(failures)
                    end)
                    return
                end
                press_thumbnail(space_id, screen_id, timing, focus, function(error_message)
                    if error_message then
                        table.insert(failures, error_message)
                    end
                    on_done(failures)
                end)
            end)
        end, function(error_message)
            if focus then
                log_failure_after_focus(describe_desktop(space_id), focus, error_message)
            end
            on_done({ error_message })
        end)
    end)
end

---Opens Mission Control once, adds and removes the desktops of every edit, one screen after
---another, and closes Mission Control by a toggle.
---Right before each removal, a desktop that shows or that holds a window that keeps it stays, and
---the console notes it.
---@param edits DesktopEdit[]
---@param find_keeping_window fun(window_ids: integer[]): integer|nil the window among those that
---macOS lists on a desktop to remove that keeps the desktop, or nil when none keeps it
---@param timing Timing
---@param on_done fun(failures: string[])
function mission_control_desktops.edit(edits, find_keeping_window, timing, on_done)
    run_opening(edits, nil, find_keeping_window, timing, nil, on_done)
end

---Opens Mission Control once, applies the edits as `edit` does, and then shows the desktop by a
---press on its thumbnail, at the position that it has after the removals.
---When the desktop shows already, Mission Control closes by a toggle instead.
---@param edits DesktopEdit[]
---@param space_id integer
---@param find_keeping_window fun(window_ids: integer[]): integer|nil
---@param timing Timing
---@param on_done fun(failures: string[])
function mission_control_desktops.edit_and_show_space(
    edits,
    space_id,
    find_keeping_window,
    timing,
    on_done
)
    run_opening(edits, space_id, find_keeping_window, timing, nil, on_done)
end

---Stops the openings that run, so that their later steps focus, open, press, add and remove
---nothing and their callbacks are not called, and closes Mission Control by a toggle when the
---group of a display shows, as after a step of the desktop manager that stopped halfway.
---@return boolean whether Mission Control showed
function mission_control_desktops.stop_openings()
    stopped_count = stopped_count + 1
    for _, screen in ipairs(hs.screen.allScreens()) do
        if find_display_group(screen:id()) then
            hs.spaces.toggleMissionControl()
            return true
        end
    end
    return false
end

---Shows the desktop, or a space in full screen, by a press on its thumbnail in Mission Control,
---and waits until its screen reports it.
---With a chosen window, the press may first focus another window of its application, as
---`focus_before_press.find_window_to_focus` says, and waits until the application is frontmost.
---`on_done` receives nil once the desktop is active, at once when it shows already, or a message
---that says why it is not.
---@param space_id integer
---@param timing Timing
---@param on_done fun(error_message: string|nil)
---@param chosen_window ChosenWindow|nil the window that the press brings to the front
function mission_control_desktops.show_space(space_id, timing, on_done, chosen_window)
    run_opening(
        {},
        space_id,
        function()
            return nil
        end,
        timing,
        chosen_window,
        function(failures)
            on_done(failures[1])
        end
    )
end

return mission_control_desktops
