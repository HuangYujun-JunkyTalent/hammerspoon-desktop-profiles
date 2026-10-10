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

---@param desktop_count integer
---@param records WindowRecord[]
---@return Arrangement
local function arrangement_with(desktop_count, records)
    return {
        monitor_configuration_key = "built-in",
        monitors = { { slot_key = "built-in", desktop_count = desktop_count } },
        focus = { slot_key = "built-in", desktop_number = 2 },
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

return {
    a_window_on_its_desktop_needs_only_its_frame = function()
        local record = record_on(41, 2)
        local plan = restore_plan.plan(
            arrangement_with(2, { record }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = record, window_id = 41 } },
            {
                [41] = {
                    bundle_id = "com.apple.Safari",
                    space_id = 14,
                    is_minimized = false,
                    is_app_hidden = false,
                },
            }
        )
        expect.equal(#plan.placements_in_place, 1)
        expect.equal(plan.visits, {})
        expect.equal(plan.desktop_additions, {})
        expect.equal(plan.focus, { screen_uuid = "BUILTIN-UUID", desktop_number = 2 })
    end,

    a_window_on_another_desktop_of_its_screen_stays = function()
        local record = record_on(41, 2)
        local plan = restore_plan.plan(
            arrangement_with(2, { record }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = record, window_id = 41 } },
            {
                [41] = {
                    bundle_id = "com.apple.Safari",
                    space_id = 3,
                    is_minimized = false,
                    is_app_hidden = true,
                },
            }
        )
        expect.equal(plan.bundle_ids_to_unhide, { "com.apple.Safari" })
        expect.equal(plan.window_ids_off_desktop, { 41 })
        expect.equal(plan.visits, {})
    end,

    a_window_stays_in_place_while_desktops_are_added = function()
        local record = record_on(41, 2)
        local plan = restore_plan.plan(
            arrangement_with(3, { record }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = record, window_id = 41 } },
            {
                [41] = {
                    bundle_id = "com.apple.Safari",
                    space_id = 14,
                    is_minimized = false,
                    is_app_hidden = false,
                },
            }
        )
        expect.equal(
            plan.desktop_additions,
            { { screen_uuid = "BUILTIN-UUID", desktops_to_add = 1 } }
        )
        expect.equal(#plan.placements_in_place, 1)
        expect.equal(plan.visits, {})
    end,

    a_minimized_window_on_its_desktop_is_unminimized_in_place = function()
        local record = record_on(41, 2)
        local plan = restore_plan.plan(
            arrangement_with(2, { record }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = record, window_id = 41 } },
            {
                [41] = {
                    bundle_id = "com.apple.Safari",
                    space_id = 14,
                    is_minimized = true,
                    is_app_hidden = false,
                },
            }
        )
        expect.equal(#plan.unminimizations_in_place, 1)
        expect.equal(plan.unminimizations_in_place[1].window_id, 41)
        expect.equal(plan.placements_in_place, {})
        expect.equal(plan.visits, {})
    end,

    a_minimized_window_on_another_desktop_is_unminimized_where_it_is = function()
        local record = record_on(41, 2)
        local plan = restore_plan.plan(
            arrangement_with(2, { record }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = record, window_id = 41 } },
            {
                [41] = {
                    bundle_id = "com.apple.Safari",
                    space_id = 3,
                    is_minimized = true,
                    is_app_hidden = false,
                },
            }
        )
        expect.equal(plan.unminimizations_in_place[1].window_id, 41)
        expect.equal(plan.visits, {})
    end,

    placements_are_grouped_by_desktop = function()
        local visits = restore_plan.group_into_visits({
            { window_id = 41, screen_uuid = "A", desktop_number = 2 },
            { window_id = 42, screen_uuid = "A", desktop_number = 1 },
            { window_id = 43, screen_uuid = "A", desktop_number = 2 },
        })
        expect.equal(#visits, 2)
        expect.equal(visits[1].desktop_number, 2)
        expect.equal(#visits[1].placements, 2)
        expect.equal(visits[2].placements[1].window_id, 42)
    end,

    missing_desktops_are_added_and_extra_ones_stay = function()
        local plan_adding = restore_plan.plan(
            arrangement_with(4, {}),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            {},
            {}
        )
        expect.equal(
            plan_adding.desktop_additions,
            { { screen_uuid = "BUILTIN-UUID", desktops_to_add = 2 } }
        )
        local plan_keeping = restore_plan.plan(
            arrangement_with(2, {}),
            CONFIGURATION,
            layout_with({ 3, 14, 64, 163 }),
            {},
            {}
        )
        expect.equal(plan_keeping.desktop_additions, {})
    end,

    a_window_recorded_out_of_sight_is_left_to_the_concealment = function()
        local record = record_on(41, 1)
        record.is_out_of_sight = true
        local plan = restore_plan.plan(
            arrangement_with(2, { record }),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            { { record = record, window_id = 41 } },
            {
                [41] = {
                    bundle_id = "com.apple.Safari",
                    space_id = 3,
                    is_minimized = false,
                    is_app_hidden = true,
                },
            }
        )
        expect.equal(plan.bundle_ids_to_unhide, {})
        expect.equal(plan.placements_in_place, {})
        expect.equal(plan.unminimizations_in_place, {})
        expect.equal(plan.visits, {})
    end,

    a_window_recorded_on_another_screen_goes_on_a_visit_ordered_by_desktop = function()
        local external_frame = { x = 1440, y = 0, w = 1920, h = 1080 }
        local configuration = monitor_configuration.describe({
            {
                uuid = "BUILTIN-UUID",
                name = "Built-in Retina Display",
                is_builtin = true,
                frame = BUILTIN_FRAME,
            },
            {
                uuid = "EXTERNAL-UUID",
                name = "LG TV SSCR2",
                is_builtin = false,
                frame = external_frame,
            },
        }, monitor_matching.BY_COUNT)
        local layout = {
            screens = {
                {
                    screen_uuid = "BUILTIN-UUID",
                    screen_frame = BUILTIN_FRAME,
                    space_ids = { 3, 14 },
                    active_space_id = 3,
                },
                {
                    screen_uuid = "EXTERNAL-UUID",
                    screen_frame = external_frame,
                    space_ids = { 7, 8, 9 },
                    active_space_id = 7,
                },
            },
            focused_space_id = 3,
        }
        local first, second = record_on(41, 3), record_on(42, 2)
        first.slot_key, second.slot_key = "external 1", "external 1"
        local in_sight_on_builtin = {
            bundle_id = "com.apple.Safari",
            space_id = 3,
            is_minimized = false,
            is_app_hidden = false,
        }
        local plan = restore_plan.plan(
            {
                monitor_configuration_key = configuration.key,
                monitors = {
                    { slot_key = "built-in", desktop_count = 2 },
                    { slot_key = "external 1", desktop_count = 3 },
                },
                focus = nil,
                windows = { first, second },
            },
            configuration,
            layout,
            { { record = first, window_id = 41 }, { record = second, window_id = 42 } },
            { [41] = in_sight_on_builtin, [42] = in_sight_on_builtin }
        )
        expect.equal(#plan.visits, 2)
        expect.equal(plan.visits[1].screen_uuid, "EXTERNAL-UUID")
        expect.equal(plan.visits[1].desktop_number, 2)
        expect.equal(plan.visits[2].desktop_number, 3)
        expect.equal(plan.window_ids_off_desktop, {})
    end,
}
