local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local fake_worlds = require("tests.fake_worlds")
local mission_control_desktops = require("desktop_manager.macos.mission_control_desktops")
local retained_timers = require("desktop_manager.macos.retained_timers")

local BUILTIN_SCREEN = fake_worlds.build_builtin_screen()
local DELL_SCREEN = fake_worlds.build_dell_screen()
local SETTLE_SECONDS = 30
local DESKTOP_2 = "desktop 2 of Built-in Retina Display"
local NO_FOCUS = ": no focus before the press, "
local LOG_OF_TWO_IGNORED_PRESSES = DESKTOP_2
    .. NO_FOCUS
    .. "not active after 5.05 seconds, "
    .. "Mission Control still showed after 5.05 seconds and closed by a toggle, "
    .. "a second press after 2.00 seconds"
local WARNING_OF_TWO_IGNORED_PRESSES = DESKTOP_2
    .. " did not show. "
    .. "Its screen shows desktop 1 of Built-in Retina Display, "
    .. "and Mission Control still showed at the end of the wait. No press failed."
local LOG_OF_A_SECOND_PRESS = DESKTOP_2
    .. NO_FOCUS
    .. "active after 2.05 seconds, "
    .. "Mission Control closed after 2.05 seconds, a second press after 2.00 seconds"
local LOG_OF_A_FAILED_SECOND_PRESS = DESKTOP_2
    .. NO_FOCUS
    .. "active after 3.05 seconds, "
    .. "Mission Control closed after 3.05 seconds, a second press after 2.00 seconds, "
    .. "which failed: Mission Control rejected AXPress: the element is gone"
local LOG_OF_A_SECOND_OPENING = DESKTOP_2
    .. NO_FOCUS
    .. "not active after 7.45 seconds, "
    .. "Mission Control had closed by 7.45 seconds, "
    .. "a second opening after 2.00 seconds and a second press after 2.40 seconds"
local WARNING_OF_NO_SECOND_PRESS = DESKTOP_2
    .. " did not show. "
    .. "Its screen shows desktop 1 of Built-in Retina Display, "
    .. "and Mission Control had closed at the end of the wait. No press failed."
local WARNING_OF_A_FAILED_SECOND_PRESS = DESKTOP_2
    .. " did not show. "
    .. "Its screen shows desktop 1 of Built-in Retina Display, "
    .. "and Mission Control still showed at the end of the wait. "
    .. "The second press failed: Mission Control rejected AXPress: the element is gone."
local LOG_OF_A_SECOND_OPENING_AFTER_A_BOUNCE = "desktop 2 of DELL S2725DS"
    .. NO_FOCUS
    .. "active after 3.45 seconds, Mission Control closed after 3.45 seconds, "
    .. "a second opening after 2.00 seconds and a second press after 2.40 seconds"
local FOCUS_OF_A_FAILED_PRESS = "desktop 2 of DELL S2725DS: "
    .. 'Code window "future-work.tex" focused before the press, frontmost after 0.00 seconds. '
local LOG_OF_A_FAILED_SECOND_OPENING = "desktop 2 of DELL S2725DS"
    .. NO_FOCUS
    .. "not active after 2.80 seconds, Mission Control had closed by 2.80 seconds, "
    .. "a second opening after 2.00 seconds, which failed: "
local LOG_OF_A_FOCUS_BEFORE_THE_PRESS = "desktop 2 of DELL S2725DS: "
    .. 'Code window "future-work.tex" focused before the press, frontmost after 0.00 seconds, '
    .. "active after 1.05 seconds, Mission Control closed after 1.05 seconds, one press"
local LOG_OF_A_PRESS_CLOSED_BY_A_TOGGLE = DESKTOP_2
    .. NO_FOCUS
    .. "active after 0.00 seconds, "
    .. "Mission Control still showed after 5.05 seconds and closed by a toggle, one press"

---A world with the built-in display and a Dell monitor, each showing its first desktop, and a
---window of Safari on the second desktop of the built-in display.
---@param builtin_space_ids integer[]
---@param dell_space_ids integer[]
---@return table world
local function start_world(builtin_space_ids, dell_space_ids)
    return fake_hammerspoon.install({
        screens = { BUILTIN_SCREEN, DELL_SCREEN },
        displays = fake_worlds.build_two_displays(builtin_space_ids, dell_space_ids),
        applications = { { bundle_id = "com.apple.Safari", name = "Safari", is_running = true } },
        windows = {
            {
                id = 41,
                bundle_id = "com.apple.Safari",
                title = "Inbox",
                space_id = builtin_space_ids[2],
                frame = { x = 0, y = 25, w = 720, h = 875 },
            },
        },
    })
end

---@param screen table
---@param desktops_to_add integer
---@param space_ids_to_remove integer[]
---@return DesktopEdit
local function edit_of(screen, desktops_to_add, space_ids_to_remove)
    return {
        screen_uuid = screen.uuid,
        slot_key = screen.name,
        desktops_to_add = desktops_to_add,
        space_ids_to_remove = space_ids_to_remove,
    }
end

local function keep_no_desktop()
    return nil
end

---@param world table
---@return number seconds from the first press on a thumbnail to the second
local function measure_second_press(world)
    return world.desktop_presses[2].at - world.desktop_presses[1].at
end

---@param seconds number
---@param low number
---@param high number
local function expect_between(seconds, low, high)
    if seconds < low or seconds >= high then
        error(string.format("expected at least %g and less than %g, got %g", low, high, seconds), 2)
    end
end

---Advances the world in steps of 0.01 seconds until `is_met` returns true, and fails the test
---when it is still false after `SETTLE_SECONDS`.
---@param world table
---@param is_met fun(): boolean
local function advance_until(world, is_met)
    local deadline = world.clock + SETTLE_SECONDS
    while not is_met() do
        if world.clock >= deadline then
            error("the condition still failed after " .. SETTLE_SECONDS .. " seconds", 2)
        end
        world.advance(0.01)
    end
end

---Shows desktop 2 of the built-in display and advances the world to its first press.
---@param world table
---@return table state whose field `result` is "pending", "shown", or the message of the failure
local function start_press(world)
    local state = { result = "pending" }
    mission_control_desktops.show_space(
        14,
        fake_worlds.create_default_timing(),
        function(error_message)
            state.result = error_message or "shown"
        end
    )
    while #world.desktop_presses == 0 do
        world.advance(0.01)
    end
    return state
end

---Makes every read of the desktops fail from `from_seconds` to `until_seconds` from now.
---@param world table
---@param from_seconds number
---@param until_seconds number
local function fail_desktop_reads(world, from_seconds, until_seconds)
    world.schedule(from_seconds, function()
        world.desktop_read_error = "macOS did not report its desktops: transient"
    end)
    world.schedule(until_seconds, function()
        world.desktop_read_error = nil
    end)
end

---@param world table
---@param space_id integer
---@return string result "shown", or the message of the failure, once the world has settled
local function show_and_settle(world, space_id)
    local result = "pending"
    mission_control_desktops.show_space(
        space_id,
        fake_worlds.create_default_timing(),
        function(error_message)
            result = error_message or "shown"
        end
    )
    world.advance(SETTLE_SECONDS)
    return result
end

local VS_CODE = "com.microsoft.VSCode"
local FUTURE_WORK_ID = 61
local PRESENTATIONS_ID = 62
local PRESENTATIONS = { bundle_id = VS_CODE, window_id = PRESENTATIONS_ID }
local REFUSED_PRESS = "Mission Control rejected AXPress: the element is gone"
local SEARCH_FAILURE = "Finding the window to focus before the press failed: "
local PRESS_EFFECT_SECONDS = 1.01
local BOUNCE_SECONDS = 0.02

---The desktops of the presses of the work record of 2026-10-19 14:58: Slack in front on the
---built-in display, and on the Dell monitor desktop 1 with the VS Code window "future-work.tex",
---which VS Code focused last, and desktop 2 with the VS Code window "Presentations".
---A press takes effect after about one second, and the fake models the bounce shortly after.
---@return table world
local function start_bounce_world()
    local world = fake_hammerspoon.install({
        screens = { BUILTIN_SCREEN, DELL_SCREEN },
        displays = fake_worlds.build_two_displays({ 3 }, { 7, 8, 9 }),
        applications = {
            { bundle_id = "com.tinyspeck.slackmacgap", name = "Slack", is_running = true },
            { bundle_id = VS_CODE, name = "Code", is_running = true },
        },
        windows = {
            {
                id = 51,
                bundle_id = "com.tinyspeck.slackmacgap",
                title = "general",
                space_id = 3,
                frame = { x = 0, y = 25, w = 1440, h = 875 },
            },
            {
                id = FUTURE_WORK_ID,
                bundle_id = VS_CODE,
                title = "future-work.tex",
                space_id = 7,
                frame = { x = 1440, y = 0, w = 2560, h = 1415 },
            },
            {
                id = PRESENTATIONS_ID,
                bundle_id = VS_CODE,
                title = "Presentations",
                space_id = 8,
                frame = { x = 1440, y = 0, w = 2560, h = 1415 },
            },
        },
    })
    world.focused_window_id = 51
    world.applications[VS_CODE].focused_window_id = FUTURE_WORK_ID
    world.desktop_press_delay_seconds = PRESS_EFFECT_SECONDS
    world.bounce_delay_seconds = BOUNCE_SECONDS
    return world
end

---Shows desktop 2 of the Dell monitor for the chosen window, or for no window.
---@param chosen_window ChosenWindow|nil
---@return table state whose field `result` is "pending", "shown", or the message of the failure
local function show_presentations_desktop(chosen_window)
    local state = { result = "pending" }
    mission_control_desktops.show_space(
        8,
        fake_worlds.create_default_timing(),
        function(error_message)
            state.result = error_message or "shown"
        end,
        chosen_window
    )
    return state
end

---@param world table
---@return boolean whether a window got the focus before the first press on a thumbnail
local function was_focused_before_the_press(world)
    for _, operation in ipairs(world.window_operations) do
        if operation:match("^focus ") then
            return true
        end
    end
    return false
end

return {
    one_opening_adds_the_desktops_of_two_screens = function()
        local world = start_world({ 3, 14 }, { 7 })
        local failures = nil
        mission_control_desktops.edit(
            { edit_of(BUILTIN_SCREEN, 1, {}), edit_of(DELL_SCREEN, 2, {}) },
            keep_no_desktop,
            fake_worlds.create_default_timing(),
            function(edit_failures)
                failures = edit_failures
            end
        )
        world.advance(SETTLE_SECONDS)
        expect.equal(failures, {})
        expect.equal(world.mission_control_actions, { "add 2000", "add 2001", "add 2002" })
        expect.equal(world.displays[2].space_ids, { 7, 2001, 2002 })
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.is_mission_control_open, false)
    end,

    one_opening_removes_the_desktops_of_two_screens_and_then_shows_a_desktop = function()
        local world = start_world({ 3, 14, 64, 65 }, { 7, 8, 9 })
        local failures = nil
        mission_control_desktops.edit_and_show_space(
            { edit_of(BUILTIN_SCREEN, 0, { 64, 65 }), edit_of(DELL_SCREEN, 0, { 9 }) },
            14,
            keep_no_desktop,
            fake_worlds.create_default_timing(),
            function(edit_failures)
                failures = edit_failures
            end
        )
        world.advance(SETTLE_SECONDS)
        expect.equal(failures, {})
        expect.equal(
            world.mission_control_actions,
            { "remove 65", "remove 64", "remove 9", "show 14" }
        )
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.is_mission_control_open, false)
    end,

    the_press_after_a_removal_finds_the_thumbnail_at_its_new_position = function()
        local world = start_world({ 3, 14 }, { 7, 8, 9 })
        local failures = nil
        mission_control_desktops.edit_and_show_space(
            { edit_of(DELL_SCREEN, 0, { 8 }) },
            9,
            keep_no_desktop,
            fake_worlds.create_default_timing(),
            function(edit_failures)
                failures = edit_failures
            end
        )
        world.advance(SETTLE_SECONDS)
        expect.equal(failures, {})
        expect.equal(world.mission_control_actions, { "remove 8", "show 9" })
        expect.equal(world.displays[2].active_space_id, 9)
        expect.equal(world.focused_display_uuid, DELL_SCREEN.uuid)
    end,

    an_edit_that_ends_on_a_desktop_in_view_closes_mission_control_by_a_toggle = function()
        local world = start_world({ 3, 14, 64 }, { 7 })
        local failures = nil
        mission_control_desktops.edit_and_show_space(
            { edit_of(BUILTIN_SCREEN, 0, { 64 }) },
            3,
            keep_no_desktop,
            fake_worlds.create_default_timing(),
            function(edit_failures)
                failures = edit_failures
            end
        )
        world.advance(SETTLE_SECONDS)
        expect.equal(failures, {})
        expect.equal(world.mission_control_actions, { "remove 64" })
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.is_mission_control_open, false)
    end,

    a_desktop_that_shows_or_holds_a_window_that_keeps_it_stays_at_the_removal = function()
        local world = start_world({ 3, 14, 64, 65 }, { 7 })
        world.displays[1].active_space_id = 65
        local failures = nil
        mission_control_desktops.edit(
            { edit_of(BUILTIN_SCREEN, 0, { 14, 64, 65 }) },
            function(window_ids)
                for _, window_id in ipairs(window_ids) do
                    if window_id == 41 then
                        return window_id
                    end
                end
                return nil
            end,
            fake_worlds.create_default_timing(),
            function(edit_failures)
                failures = edit_failures
            end
        )
        world.advance(SETTLE_SECONDS)
        expect.equal(failures, {})
        expect.equal(world.mission_control_actions, { "remove 64" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 65 })
        expect.equal(world.is_mission_control_open, false)
    end,

    a_space_in_full_screen_between_desktops_counts_in_the_positions_of_the_thumbnails = function()
        local world = start_world({ 3, 14, 64 }, { 7 })
        world.displays[1].full_screen_space_ids = { 500 }
        world.displays[1].all_space_ids = { 3, 500, 14, 64 }
        local failures = nil
        mission_control_desktops.edit(
            { edit_of(BUILTIN_SCREEN, 0, { 64 }) },
            keep_no_desktop,
            fake_worlds.create_default_timing(),
            function(edit_failures)
                failures = edit_failures
            end
        )
        world.advance(SETTLE_SECONDS)
        expect.equal(failures, {})
        expect.equal(world.displays[1].space_ids, { 3, 14 })
        expect.equal(show_and_settle(world, 14), "shown")
        expect.equal(world.mission_control_actions, { "remove 64", "show 14" })
        expect.equal(world.displays[1].active_space_id, 14)
    end,

    a_space_in_full_screen_shows_through_its_thumbnail = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.displays[1].full_screen_space_ids = { 500 }
        expect.equal(show_and_settle(world, 500), "shown")
        expect.equal(world.mission_control_actions, { "show 500" })
        expect.equal(world.displays[1].active_space_id, 500)
    end,

    an_opening_that_was_stopped_removes_no_further_desktop_and_ends_nothing = function()
        local world = start_world({ 3, 14, 64, 65 }, { 7 })
        local is_done = false
        mission_control_desktops.edit(
            { edit_of(BUILTIN_SCREEN, 0, { 64, 65 }) },
            keep_no_desktop,
            fake_worlds.create_default_timing(),
            function()
                is_done = true
            end
        )
        while #world.mission_control_actions == 0 do
            world.advance(0.05)
        end
        expect.equal(mission_control_desktops.stop_openings(), true)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "remove 65" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.is_mission_control_open, false)
        expect.equal(is_done, false)
    end,

    a_desktop_that_shows_needs_no_opening = function()
        local world = start_world({ 3, 14 }, { 7 })
        expect.equal(show_and_settle(world, 7), "shown")
        expect.equal(world.mission_control_openings, 0)
        expect.equal(world.mission_control_actions, {})
    end,

    mission_control_waits_for_the_release_of_the_modifiers = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.held_modifiers = { alt = true }
        local result = "pending"
        mission_control_desktops.show_space(
            14,
            fake_worlds.create_default_timing(),
            function(error_message)
                result = error_message or "shown"
            end
        )
        world.advance(1)
        expect.equal(world.mission_control_openings, 0)
        world.held_modifiers = {}
        world.advance(SETTLE_SECONDS)
        expect.equal(result, "shown")
        expect.equal(world.mission_control_actions, { "show 14" })
        expect.equal(world.mission_control_openings, 1)
    end,

    mission_control_stays_closed_while_the_modifiers_are_held = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.held_modifiers = { alt = true }
        local result = show_and_settle(world, 14)
        expect.equal(
            result,
            "Release the modifier keys: Mission Control stays closed while they are held,"
                .. " and they were held for 3 seconds"
        )
        expect.equal(world.mission_control_openings, 0)
        expect.equal(world.displays[1].active_space_id, 3)
    end,

    a_desktop_that_mission_control_never_shows_fails_after_5_seconds_and_two_presses = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignores_desktop_presses = true
        local timers_before = retained_timers.count_running()
        local result = "pending"
        mission_control_desktops.show_space(
            14,
            fake_worlds.create_default_timing(),
            function(error_message)
                result = error_message or "shown"
            end
        )
        while #world.desktop_presses == 0 do
            world.advance(0.05)
        end
        world.advance(4.9)
        expect.equal(result, "pending")
        world.advance(SETTLE_SECONDS)
        expect.equal(
            result,
            "Mission Control did not show desktop 2 of Built-in Retina Display within 5 seconds,"
                .. " after one opening and two presses"
        )
        expect.equal(#world.desktop_presses, 2)
        expect_between(measure_second_press(world), 2, 2.1)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.log_lines[#world.log_lines - 1], LOG_OF_TWO_IGNORED_PRESSES)
        expect.equal(world.log_lines[#world.log_lines], WARNING_OF_TWO_IGNORED_PRESSES)
        expect.equal(retained_timers.count_running(), timers_before)
    end,

    a_press_that_takes_effect_after_3_seconds_shows_the_desktop = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.desktop_press_delay_seconds = 3
        expect.equal(show_and_settle(world, 14), "shown")
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(#world.desktop_presses, 2)
        expect_between(measure_second_press(world), 2, 2.1)
    end,

    a_press_that_mission_control_ignores_once_is_made_again_after_2_seconds = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignored_desktop_press_count = 1
        expect.equal(show_and_settle(world, 14), "shown")
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.mission_control_actions, { "show 14" })
        expect.equal(#world.desktop_presses, 2)
        expect_between(measure_second_press(world), 2, 2.1)
        expect.equal(world.log_lines[#world.log_lines], LOG_OF_A_SECOND_PRESS)
    end,

    the_second_press_finds_the_thumbnail_anew = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignored_desktop_press_count = 1
        world.makes_thumbnails_stale = true
        expect.equal(show_and_settle(world, 14), "shown")
        expect.equal(#world.desktop_presses, 2)
    end,

    until_the_desktop_is_active_only_the_second_check_reads_the_tree_of_window_manager = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.desktop_press_delay_seconds = 3
        expect.equal(show_and_settle(world, 14), "shown")
        local first_press, second_press = world.desktop_presses[1], world.desktop_presses[2]
        expect.equal(second_press.window_manager_reads - first_press.window_manager_reads, 1)
    end,

    an_error_of_the_second_press_is_logged_and_ends_nothing = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.desktop_press_delay_seconds = 3
        world.desktop_press_refusals = { [2] = "the element is gone" }
        expect.equal(show_and_settle(world, 14), "shown")
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.log_lines[#world.log_lines], LOG_OF_A_FAILED_SECOND_PRESS)
    end,

    a_second_opening_follows_once_mission_control_has_closed_and_is_the_last = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignores_desktop_presses = true
        world.on_mission_control_open = function()
            world.schedule(1.5, function()
                world.is_mission_control_open = false
            end)
        end
        local state = start_press(world)
        advance_until(world, function()
            return #world.desktop_presses == 2
        end)
        world.advance(4.9)
        expect.equal(state.result, "pending")
        world.advance(SETTLE_SECONDS)
        expect.equal(
            state.result,
            "Mission Control did not show desktop 2 of Built-in Retina Display within 5 seconds,"
                .. " after two openings and two presses"
        )
        expect.equal(#world.desktop_presses, 2)
        expect.equal(world.mission_control_openings, 2)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.log_lines[#world.log_lines - 1], LOG_OF_A_SECOND_OPENING)
        expect.equal(world.log_lines[#world.log_lines], WARNING_OF_NO_SECOND_PRESS)
    end,

    the_desktop_that_became_active_right_before_the_second_opening_opens_nothing = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignores_desktop_presses = true
        world.on_mission_control_open = function()
            world.schedule(1.5, function()
                world.is_mission_control_open = false
            end)
        end
        local state = start_press(world)
        local first_press_at = world.desktop_presses[1].at
        world.on_window_manager_read = function()
            if world.clock >= first_press_at + 2 then
                world.displays[1].active_space_id = 14
            end
        end
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "shown")
        expect.equal(#world.desktop_presses, 1)
        expect.equal(world.mission_control_openings, 1)
    end,

    a_desktop_that_is_active_while_mission_control_still_shows_gets_no_second_press = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.mission_control_close_delay_seconds = 2.5
        local result = "pending"
        mission_control_desktops.show_space(
            14,
            fake_worlds.create_default_timing(),
            function(error_message)
                result = error_message or "shown"
            end
        )
        while #world.desktop_presses == 0 do
            world.advance(0.05)
        end
        world.advance(2.4)
        expect.equal(result, "pending")
        world.advance(SETTLE_SECONDS)
        expect.equal(result, "shown")
        expect.equal(#world.desktop_presses, 1)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.is_mission_control_open, false)
    end,

    a_desktop_that_is_active_at_the_end_of_the_wait_counts_as_shown = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.mission_control_close_delay_seconds = 10
        expect.equal(show_and_settle(world, 14), "shown")
        expect.equal(#world.desktop_presses, 1)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.log_lines[#world.log_lines], LOG_OF_A_PRESS_CLOSED_BY_A_TOGGLE)
    end,

    a_stopped_press_presses_nothing_more_and_calls_nothing_back = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignores_desktop_presses = true
        local timers_before = retained_timers.count_running()
        local is_done = false
        mission_control_desktops.show_space(14, fake_worlds.create_default_timing(), function()
            is_done = true
        end)
        while #world.desktop_presses == 0 do
            world.advance(0.05)
        end
        world.advance(1)
        expect.equal(mission_control_desktops.stop_openings(), true)
        world.advance(SETTLE_SECONDS)
        expect.equal(#world.desktop_presses, 1)
        expect.equal(is_done, false)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(retained_timers.count_running(), timers_before)
    end,

    a_failed_read_of_the_desktops_during_the_wait_ends_nothing = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.swallows_timer_errors = true
        world.ignores_desktop_presses = true
        local state = start_press(world)
        fail_desktop_reads(world, 0, 0.2)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.timer_errors, {})
        expect.equal(
            state.result,
            "Mission Control did not show desktop 2 of Built-in Retina Display within 5 seconds,"
                .. " after one opening and two presses"
        )
        expect.equal(#world.desktop_presses, 2)
        expect.equal(world.is_mission_control_open, false)
    end,

    a_failed_read_of_the_desktops_at_the_second_check_is_logged_and_ends_nothing = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.swallows_timer_errors = true
        world.ignores_desktop_presses = true
        local state = start_press(world)
        fail_desktop_reads(world, 1.9, 2.1)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.timer_errors, {})
        expect.equal(
            state.result,
            "Mission Control did not show desktop 2 of Built-in Retina Display within 5 seconds,"
                .. " after one opening and one press"
        )
        expect.equal(#world.desktop_presses, 1)
        expect.equal(world.is_mission_control_open, false)
        local warning = world.log_lines[#world.log_lines]
        expect.present(
            warning:find("At the second check, reading the desktops failed: ", 1, true),
            "the failed reading in the warning"
        )
    end,

    a_failed_read_of_the_desktops_at_the_end_of_the_wait_ends_the_press = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.swallows_timer_errors = true
        world.ignores_desktop_presses = true
        local state = start_press(world)
        fail_desktop_reads(world, 4.9, 6)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.timer_errors, {})
        expect.equal(
            state.result,
            "Mission Control did not show desktop 2 of Built-in Retina Display within 5 seconds,"
                .. " after one opening and two presses"
        )
        expect.equal(world.is_mission_control_open, false)
        expect.equal(
            world.log_lines[#world.log_lines],
            DESKTOP_2
                .. " did not show. Its screen shows no desktop, and Mission Control still showed"
                .. " at the end of the wait. No press failed."
        )
    end,

    a_stop_during_the_settle_after_the_end_of_the_wait_calls_nothing_back = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.mission_control_close_delay_seconds = 10
        local state = start_press(world)
        while world.is_mission_control_open do
            world.advance(0.01)
        end
        world.advance(0.42)
        expect.equal(state.result, "pending")
        mission_control_desktops.stop_openings()
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "pending")
    end,

    a_stop_during_the_settle_after_a_shown_desktop_calls_nothing_back = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.desktop_press_delay_seconds = 1
        local state = start_press(world)
        while world.displays[1].active_space_id ~= 14 do
            world.advance(0.01)
        end
        world.advance(0.06)
        expect.equal(state.result, "pending")
        mission_control_desktops.stop_openings()
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "pending")
    end,

    the_warning_gives_the_error_of_the_second_press = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignores_desktop_presses = true
        world.desktop_press_refusals = { [2] = "the element is gone" }
        start_press(world)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.log_lines[#world.log_lines], WARNING_OF_A_FAILED_SECOND_PRESS)
    end,

    a_missing_thumbnail_at_the_second_check_is_logged = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignores_desktop_presses = true
        start_press(world)
        world.displays[1].space_ids = { 3 }
        world.advance(SETTLE_SECONDS)
        local warning = world.log_lines[#world.log_lines]
        local cause = "At the second check, Mission Control listed no thumbnail"
        expect.present(warning:find(cause, 1, true), "the cause in the warning")
    end,

    without_the_focus_a_press_from_another_application_bounces_and_opens_again = function()
        local world = start_bounce_world()
        local state = show_presentations_desktop(nil)
        while #world.desktop_presses == 0 do
            world.advance(0.01)
        end
        local first_press_at = world.desktop_presses[1].at
        world.advance(1.9)
        expect.equal(world.displays[2].active_space_id, 7)
        expect.equal(world.focused_window_id, FUTURE_WORK_ID)
        expect.equal(#world.bounces, 1)
        expect_between(world.bounces[1].at - first_press_at, 1, 1.1)
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "shown")
        expect.equal(world.displays[2].active_space_id, 8)
        expect.equal(#world.bounces, 1)
        expect.equal(#world.desktop_presses, 2)
        expect.equal(world.mission_control_openings, 2)
        expect.equal(world.log_lines[#world.log_lines], LOG_OF_A_SECOND_OPENING_AFTER_A_BOUNCE)
    end,

    a_failed_second_opening_ends_the_press_with_a_failure_that_says_so = function()
        local world = start_bounce_world()
        local state = show_presentations_desktop(nil)
        world.advance(1.9)
        world.held_modifiers = { alt = true }
        world.advance(SETTLE_SECONDS)
        expect.equal(
            state.result,
            "Mission Control did not show desktop 2 of DELL S2725DS after one press,"
                .. " and the second opening failed: Release the modifier keys: Mission Control"
                .. " stays closed while they are held, and they were held for 3 seconds"
        )
        expect.equal(world.displays[2].active_space_id, 7)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(
            world.log_lines[#world.log_lines],
            "desktop 2 of DELL S2725DS"
                .. NO_FOCUS
                .. "not active after 5.05 seconds, Mission Control had closed by 5.05 seconds, "
                .. "a second opening after 2.00 seconds, which failed: Release the modifier keys:"
                .. " Mission Control stays closed while they are held, and they were held for 3"
                .. " seconds"
        )
    end,

    a_refused_press_of_the_second_opening_ends_the_press_with_a_failure_that_says_so = function()
        local world = start_bounce_world()
        world.desktop_press_refusals = { [2] = "the element is gone" }
        local state = show_presentations_desktop(nil)
        world.advance(SETTLE_SECONDS)
        expect.equal(
            state.result,
            "Mission Control did not show desktop 2 of DELL S2725DS after one press,"
                .. " and the second opening failed:"
                .. " Mission Control rejected AXPress: the element is gone"
        )
        expect.equal(world.mission_control_openings, 2)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(
            world.log_lines[#world.log_lines],
            LOG_OF_A_FAILED_SECOND_OPENING .. REFUSED_PRESS
        )
    end,

    a_second_opening_without_the_thumbnail_ends_the_press_with_a_failure_that_says_so = function()
        local world = start_bounce_world()
        local state = show_presentations_desktop(nil)
        world.on_mission_control_open = function()
            if world.mission_control_openings == 2 then
                world.displays[2].space_ids = { 7 }
            end
        end
        world.advance(SETTLE_SECONDS)
        expect.equal(
            state.result,
            "Mission Control did not show desktop 2 of DELL S2725DS after one press,"
                .. " and the second opening failed:"
                .. " Mission Control listed no thumbnail at position nil"
        )
        expect.equal(#world.desktop_presses, 1)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(
            world.log_lines[#world.log_lines],
            LOG_OF_A_FAILED_SECOND_OPENING .. "Mission Control listed no thumbnail at position nil"
        )
    end,

    a_focused_window_without_an_application_is_logged_as_other_windows_are = function()
        local world = start_bounce_world()
        world.windows_without_application[FUTURE_WORK_ID] = true
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "shown")
        expect.equal(world.window_operations, { "focus " .. FUTURE_WORK_ID })
        expect.equal(
            world.log_lines[#world.log_lines],
            "desktop 2 of DELL S2725DS: "
                .. 'a window "future-work.tex" focused before the press, frontmost after 0.00'
                .. " seconds, active after 1.05 seconds, Mission Control closed after 1.05"
                .. " seconds, one press"
        )
    end,

    the_focus_before_the_press_keeps_the_desktop_from_bouncing = function()
        local world = start_bounce_world()
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "shown")
        expect.equal(world.displays[2].active_space_id, 8)
        expect.equal(world.bounces, {})
        expect.equal(world.window_operations, { "focus " .. FUTURE_WORK_ID })
        expect.equal(#world.desktop_presses, 1)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.log_lines[#world.log_lines], LOG_OF_A_FOCUS_BEFORE_THE_PRESS)
    end,

    mission_control_opens_once_the_application_is_frontmost = function()
        local world = start_bounce_world()
        world.applications[VS_CODE].activation_delay_seconds = 0.3
        local focused_at_opening = nil
        world.on_mission_control_open = function()
            focused_at_opening = world.focused_window_id
        end
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(0.25)
        expect.equal(world.mission_control_openings, 0)
        world.advance(SETTLE_SECONDS)
        expect.equal(focused_at_opening, FUTURE_WORK_ID)
        expect.equal(state.result, "shown")
        expect.equal(world.bounces, {})
    end,

    the_press_goes_on_when_the_application_is_not_frontmost_after_1_second = function()
        local world = start_bounce_world()
        expect.equal(fake_worlds.create_default_timing().application_focus_timeout_seconds, 1)
        world.applications[VS_CODE].activation_delay_seconds = math.huge
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(0.95)
        expect.equal(world.mission_control_openings, 0)
        world.advance(0.1)
        expect.equal(world.mission_control_openings, 1)
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "shown")
        expect.equal(#world.bounces, 1)
        expect.equal(world.mission_control_openings, 2)
        local log_line = world.log_lines[#world.log_lines]
        local focus = 'Code window "future-work.tex" focused before the press,'
            .. " not frontmost after 1.00 seconds"
        expect.present(log_line:find(focus, 1, true), "the focus in the log line")
    end,

    no_focus_runs_while_the_application_is_frontmost = function()
        local world = start_bounce_world()
        world.focused_window_id = FUTURE_WORK_ID
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "shown")
        expect.equal(world.window_operations, {})
        expect.equal(world.hidden_reads[VS_CODE], nil)
        expect.equal(world.focused_window_reads[VS_CODE], nil)
        expect.equal(world.bounces, {})
    end,

    no_focus_runs_for_a_hidden_application = function()
        local world = start_bounce_world()
        world.applications[VS_CODE].is_hidden = true
        show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(was_focused_before_the_press(world), false)
        expect.equal(world.focused_window_reads[VS_CODE], nil)
    end,

    no_focus_runs_for_an_application_that_does_not_run = function()
        local world = start_bounce_world()
        world.applications[VS_CODE].is_running = false
        show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(was_focused_before_the_press(world), false)
        for _, line in ipairs(world.log_lines) do
            expect.equal(line:find("Finding the window to focus", 1, true), nil)
        end
    end,

    no_focus_runs_when_the_focused_window_lies_on_another_screen = function()
        local world = start_bounce_world()
        local elsewhere = world.add_window_of(VS_CODE, "notes.md", 3)
        world.applications[VS_CODE].focused_window_id = elsewhere.id
        show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(was_focused_before_the_press(world), false)
    end,

    no_focus_runs_when_the_window_lies_on_a_desktop_out_of_view_of_the_same_screen = function()
        local world = start_bounce_world()
        local out_of_view = world.add_window_of(VS_CODE, "notes.md", 9)
        world.applications[VS_CODE].focused_window_id = out_of_view.id
        world.applications[VS_CODE].main_window_id = out_of_view.id
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "shown")
        expect.equal(world.window_operations, {})
    end,

    a_failed_search_for_the_window_to_focus_is_logged_and_the_press_goes_on = function()
        local world = start_bounce_world()
        world.applications[VS_CODE].hidden_read_error = "the application is gone"
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "shown")
        expect.equal(world.window_operations, {})
        expect.present(
            world.log_lines[1]:find(SEARCH_FAILURE, 1, true),
            "the failed search in the first log line"
        )
        expect.equal(world.log_lines[#world.log_lines], LOG_OF_A_SECOND_OPENING_AFTER_A_BOUNCE)
    end,

    a_focus_before_an_opening_that_fails_is_logged = function()
        local world = start_bounce_world()
        world.held_modifiers = { alt = true }
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_operations, { "focus " .. FUTURE_WORK_ID })
        expect.equal(world.mission_control_openings, 0)
        local failure = "Release the modifier keys: Mission Control stays closed while they are"
            .. " held, and they were held for 3 seconds"
        expect.equal(state.result, failure)
        expect.equal(world.log_lines, { FOCUS_OF_A_FAILED_PRESS .. failure })
    end,

    a_focus_before_a_refused_first_press_is_logged = function()
        local world = start_bounce_world()
        world.desktop_press_refusals = { [1] = "the element is gone" }
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_operations, { "focus " .. FUTURE_WORK_ID })
        local failure = "Showing desktop 2 of DELL S2725DS failed:"
            .. " Mission Control rejected AXPress: the element is gone"
        expect.equal(state.result, failure)
        expect.equal(world.log_lines[#world.log_lines], FOCUS_OF_A_FAILED_PRESS .. failure)
        expect.equal(world.is_mission_control_open, false)
    end,

    a_refused_first_press_without_a_focus_writes_no_log_line_of_the_press = function()
        local world = start_bounce_world()
        world.desktop_press_refusals = { [1] = "the element is gone" }
        local state = show_presentations_desktop(nil)
        world.advance(SETTLE_SECONDS)
        expect.equal(state.result, "Showing desktop 2 of DELL S2725DS failed: " .. REFUSED_PRESS)
        for _, line in ipairs(world.log_lines) do
            expect.equal(line:find("desktop 2 of DELL S2725DS: ", 1, true), nil)
        end
    end,

    no_focus_runs_when_the_focused_window_is_the_chosen_window = function()
        local world = start_bounce_world()
        show_presentations_desktop({ bundle_id = VS_CODE, window_id = FUTURE_WORK_ID })
        world.advance(SETTLE_SECONDS)
        expect.equal(was_focused_before_the_press(world), false)
    end,

    the_main_window_counts_when_the_application_gives_no_focused_window = function()
        local world = start_bounce_world()
        world.applications[VS_CODE].focused_window_id = PRESENTATIONS_ID
        world.applications[VS_CODE].main_window_id = FUTURE_WORK_ID
        show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_operations, { "focus " .. FUTURE_WORK_ID })
    end,

    no_focus_runs_for_a_window_that_is_not_standard = function()
        local world = start_bounce_world()
        world.windows[FUTURE_WORK_ID].is_standard = false
        show_presentations_desktop(PRESENTATIONS)
        world.advance(SETTLE_SECONDS)
        expect.equal(was_focused_before_the_press(world), false)
    end,

    a_stop_during_the_wait_for_the_application_opens_nothing_and_calls_nothing_back = function()
        local world = start_bounce_world()
        world.applications[VS_CODE].activation_delay_seconds = math.huge
        local timers_before = retained_timers.count_running()
        local state = show_presentations_desktop(PRESENTATIONS)
        world.advance(0.5)
        expect.equal(mission_control_desktops.stop_openings(), false)
        world.advance(0.1)
        expect.equal(retained_timers.count_running(), timers_before)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_openings, 0)
        expect.equal(state.result, "pending")
        expect.equal(retained_timers.count_running(), timers_before)
    end,

    a_stop_during_the_second_opening_presses_nothing_more_and_calls_nothing_back = function()
        local world = start_bounce_world()
        local timers_before = retained_timers.count_running()
        local state = show_presentations_desktop(nil)
        advance_until(world, function()
            return world.mission_control_openings == 2
        end)
        expect.equal(mission_control_desktops.stop_openings(), true)
        world.advance(SETTLE_SECONDS)
        expect.equal(#world.desktop_presses, 1)
        expect.equal(state.result, "pending")
        expect.equal(world.is_mission_control_open, false)
        expect.equal(retained_timers.count_running(), timers_before)
    end,

    a_block_of_hammerspoon_past_the_deadline_still_gets_the_second_press = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignored_desktop_press_count = 1
        local state = start_press(world)
        local first_press_at = world.desktop_presses[1].at
        world.schedule(0.02, function()
            world.clock = world.clock + 6
        end)
        advance_until(world, function()
            return state.result ~= "pending"
        end)
        expect.equal(state.result, "shown")
        expect.equal(world.displays[1].active_space_id, 14)
        expect_between(measure_second_press(world), 6, 6.1)
        expect.equal(world.desktop_presses[2].at - first_press_at > 5, true)
        expect.present(
            world.log_lines[#world.log_lines]:find(
                "a second press after 6.02 seconds, Hammerspoon was blocked for up to 5.97 seconds"
                    .. " between two checks",
                1,
                true
            ),
            "the block in the log line of the press"
        )
    end,

    the_wait_after_a_second_check_that_a_block_delayed_lasts_3_seconds = function()
        local world = start_world({ 3, 14 }, { 7 })
        world.ignores_desktop_presses = true
        local state = start_press(world)
        world.schedule(0.02, function()
            world.clock = world.clock + 6
        end)
        advance_until(world, function()
            return #world.desktop_presses == 2
        end)
        local second_press_at = world.desktop_presses[2].at
        advance_until(world, function()
            return state.result ~= "pending"
        end)
        expect_between(world.clock - second_press_at, 3, 3.6)
        expect.equal(
            state.result,
            "Mission Control did not show desktop 2 of Built-in Retina Display within 5 seconds,"
                .. " after one opening and two presses"
        )
    end,
}
