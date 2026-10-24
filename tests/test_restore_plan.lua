local expect = require("tests.expect")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local restore_plan = require("desktop_manager.core.restore_plan")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }

local CONFIGURATION = monitor_configuration.describe({
    {
        uuid = "BUILTIN-UUID",
        name = "Built-in Retina Display",
        is_builtin = true,
        frame = BUILTIN_FRAME,
    },
}, monitor_matching.BY_COUNT)

---@param space_ids integer[]
---@return DesktopLayout
local function layout_with(space_ids)
    return {
        screens = {
            {
                screen_uuid = "BUILTIN-UUID",
                screen_frame = BUILTIN_FRAME,
                space_ids = space_ids,
                active_space_id = space_ids[1],
            },
        },
        focused_space_id = space_ids[1],
    }
end

local EXTERNAL_FRAME = { x = 1440, y = 0, w = 1920, h = 1080 }

local TWO_SCREENS = monitor_configuration.describe({
    {
        uuid = "BUILTIN-UUID",
        name = "Built-in Retina Display",
        is_builtin = true,
        frame = BUILTIN_FRAME,
    },
    { uuid = "EXTERNAL-UUID", name = "LG TV SSCR2", is_builtin = false, frame = EXTERNAL_FRAME },
}, monitor_matching.BY_COUNT)

---@param builtin_space_ids integer[]
---@param external_space_ids integer[]
---@return DesktopLayout
local function two_screen_layout_with(builtin_space_ids, external_space_ids)
    return {
        screens = {
            {
                screen_uuid = "BUILTIN-UUID",
                screen_frame = BUILTIN_FRAME,
                space_ids = builtin_space_ids,
                active_space_id = builtin_space_ids[1],
            },
            {
                screen_uuid = "EXTERNAL-UUID",
                screen_frame = EXTERNAL_FRAME,
                space_ids = external_space_ids,
                active_space_id = external_space_ids[1],
            },
        },
        focused_space_id = builtin_space_ids[1],
    }
end

---@param desktop_count integer
---@param records WindowRecord[]
---@return Arrangement
local function arrangement_with(desktop_count, records)
    return {
        monitor_configuration_key = "built-in",
        monitors = {
            { slot_key = "built-in", desktop_count = desktop_count, shown_desktop_number = 2 },
        },
        focused_slot_key = "built-in",
        windows = records,
    }
end

---@param window_id integer
---@param desktop_number integer
---@return WindowRecord
local function record_on(window_id, desktop_number)
    return {
        window_id = window_id,
        bundle_id = "com.apple.Safari",
        app_name = "Safari",
        title = tostring(window_id),
        slot_key = "built-in",
        desktop_number = desktop_number,
        unit_frame = { x = 0, y = 0, w = 1, h = 1 },
        is_out_of_sight = false,
    }
end

---@param is_minimized boolean
---@param is_app_hidden boolean
---@return WindowState
local function window_state(is_minimized, is_app_hidden)
    return {
        bundle_id = "com.apple.Safari",
        is_minimized = is_minimized,
        is_app_hidden = is_app_hidden,
    }
end

return {
    every_window_recorded_in_sight_is_placed = function()
        local first, second = record_on(41, 2), record_on(42, 1)
        local plan = restore_plan.plan(
            arrangement_with(2, { first, second }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = first, window_id = 41 }, { record = second, window_id = 42 } },
            { [41] = window_state(false, true), [42] = window_state(false, false) }
        )
        expect.equal(plan.placements, {
            {
                window_id = 41,
                screen_uuid = "BUILTIN-UUID",
                slot_key = "built-in",
                desktop_number = 2,
                unit_frame = { x = 0, y = 0, w = 1, h = 1 },
            },
            {
                window_id = 42,
                screen_uuid = "BUILTIN-UUID",
                slot_key = "built-in",
                desktop_number = 1,
                unit_frame = { x = 0, y = 0, w = 1, h = 1 },
            },
        })
        expect.equal(plan.bundle_ids_to_unhide, { "com.apple.Safari" })
        expect.equal(plan.unminimizations, {})
        expect.equal(plan.desktop_additions, {})
        expect.equal(
            plan.shown_desktops,
            { { screen_uuid = "BUILTIN-UUID", slot_key = "built-in", desktop_number = 2 } }
        )
    end,

    a_window_stays_in_place_while_desktops_are_added = function()
        local record = record_on(41, 2)
        local plan = restore_plan.plan(
            arrangement_with(3, { record }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = record, window_id = 41 } },
            { [41] = window_state(false, false) }
        )
        expect.equal(
            plan.desktop_additions,
            { { screen_uuid = "BUILTIN-UUID", slot_key = "built-in", desktops_to_add = 1 } }
        )
        expect.equal(plan.placements[1].desktop_number, 2)
    end,

    a_minimized_window_recorded_in_sight_is_unminimized_and_placed = function()
        local record = record_on(41, 2)
        local plan = restore_plan.plan(
            arrangement_with(2, { record }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = record, window_id = 41 } },
            { [41] = window_state(true, false) }
        )
        expect.equal(#plan.unminimizations, 1)
        expect.equal(plan.unminimizations[1].window_id, 41)
        expect.equal(plan.placements, plan.unminimizations)
    end,

    missing_desktops_are_added_with_their_slot = function()
        local plan_adding = restore_plan.plan(
            arrangement_with(4, {}),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            {},
            {}
        )
        expect.equal(
            plan_adding.desktop_additions,
            { { screen_uuid = "BUILTIN-UUID", slot_key = "built-in", desktops_to_add = 2 } }
        )
        local plan_with_extra_desktops = restore_plan.plan(
            arrangement_with(2, {}),
            CONFIGURATION,
            layout_with({ 3, 14, 64, 163 }),
            {},
            {}
        )
        expect.equal(plan_with_extra_desktops.desktop_additions, {})
    end,

    a_window_recorded_out_of_sight_is_left_to_the_concealment = function()
        local record = record_on(41, 1)
        record.is_out_of_sight = true
        local plan = restore_plan.plan(
            arrangement_with(2, { record }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = record, window_id = 41 } },
            { [41] = window_state(false, true) }
        )
        expect.equal(plan.bundle_ids_to_unhide, {})
        expect.equal(plan.placements, {})
        expect.equal(plan.unminimizations, {})
    end,

    each_screen_shows_its_recorded_desktop_with_the_screen_of_the_focus_last = function()
        local arrangement = {
            monitor_configuration_key = TWO_SCREENS.key,
            monitors = {
                { slot_key = "built-in", desktop_count = 2, shown_desktop_number = 2 },
                { slot_key = "external 1", desktop_count = 3, shown_desktop_number = 3 },
            },
            focused_slot_key = "built-in",
            windows = {},
        }
        local plan = restore_plan.plan(
            arrangement,
            TWO_SCREENS,
            two_screen_layout_with({ 3, 14 }, { 7, 8 }),
            {},
            {}
        )
        expect.equal(plan.shown_desktops, {
            { screen_uuid = "EXTERNAL-UUID", slot_key = "external 1", desktop_number = 3 },
            { screen_uuid = "BUILTIN-UUID", slot_key = "built-in", desktop_number = 2 },
        })
    end,

    a_shown_desktop_beyond_the_screen_becomes_its_last_desktop = function()
        local arrangement = arrangement_with(2, {})
        arrangement.monitors[1].shown_desktop_number = 4
        local plan = restore_plan.plan(
            arrangement,
            CONFIGURATION,
            layout_with({ 3, 14, 64, 99 }),
            {},
            {}
        )
        expect.equal(plan.shown_desktops[1].desktop_number, 2)
    end,

    a_screen_without_a_shown_desktop_leaves_a_desktop_beyond_the_number = function()
        local arrangement = arrangement_with(2, {})
        arrangement.monitors[1].shown_desktop_number = nil
        local layout = layout_with({ 3, 14, 64 })
        expect.equal(
            restore_plan.plan(arrangement, CONFIGURATION, layout, {}, {}).shown_desktops,
            {}
        )
        layout.screens[1].active_space_id = 64
        expect.equal(
            restore_plan.plan(arrangement, CONFIGURATION, layout, {}, {}).shown_desktops,
            { { screen_uuid = "BUILTIN-UUID", slot_key = "built-in", desktop_number = 2 } }
        )
    end,

    a_screen_in_full_screen_shows_its_recorded_desktop_or_its_first_one_first = function()
        local layout = two_screen_layout_with({ 3, 14 }, { 7, 8 })
        layout.screens[1].active_space_id = 900
        layout.screens[2].active_space_id = 901
        local arrangement = {
            monitor_configuration_key = TWO_SCREENS.key,
            monitors = { { slot_key = "built-in", desktop_count = 2, shown_desktop_number = 2 } },
            windows = {},
        }
        expect.equal(restore_plan.plan_exits_from_full_screen(arrangement, TWO_SCREENS, layout), {
            { screen_uuid = "BUILTIN-UUID", slot_key = "built-in", desktop_number = 2 },
            { screen_uuid = "EXTERNAL-UUID", slot_key = "external 1", desktop_number = 1 },
        })
        expect.equal(
            restore_plan.plan_exits_from_full_screen(
                nil,
                TWO_SCREENS,
                two_screen_layout_with({ 3, 14 }, { 7, 8 })
            ),
            {}
        )
    end,
}
