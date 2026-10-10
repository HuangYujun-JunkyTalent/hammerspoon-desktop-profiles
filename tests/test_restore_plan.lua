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
        is_minimized = false,
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
                    is_held_by_profile_left = false,
                },
            }
        )
        expect.equal(#plan.placements_in_place, 1)
        expect.equal(plan.visits, {})
        expect.equal(plan.desktop_count_changes, {})
        expect.equal(plan.focus, { screen_uuid = "BUILTIN-UUID", desktop_number = 2 })
    end,

    a_window_elsewhere_is_brought_on_a_visit = function()
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
                    is_held_by_profile_left = false,
                },
            }
        )
        expect.equal(plan.bundle_ids_to_unhide, { "com.apple.Safari" })
        expect.equal(plan.visits[1].desktop_number, 2)
        expect.equal(plan.visits[1].placements[1].window_id, 41)
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
                    is_held_by_profile_left = false,
                },
            }
        )
        expect.equal(#plan.unminimizations_in_place, 1)
        expect.equal(plan.unminimizations_in_place[1].window_id, 41)
        expect.equal(plan.placements_in_place, {})
        expect.equal(plan.visits, {})
    end,

    a_minimized_window_on_another_desktop_is_brought_on_a_visit = function()
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
                    is_held_by_profile_left = false,
                },
            }
        )
        expect.equal(plan.unminimizations_in_place, {})
        expect.equal(plan.visits[1].placements[1].window_id, 41)
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

    a_shared_window_on_its_desktop_is_left_alone = function()
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
                    is_held_by_profile_left = true,
                },
            }
        )
        expect.equal(plan.window_ids_left_alone, { 41 })
        expect.equal(plan.placements_in_place, {})
        expect.equal(plan.unminimizations_in_place, {})
        expect.equal(plan.visits, {})
    end,

    a_shared_window_elsewhere_is_still_brought_back = function()
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
                    is_app_hidden = false,
                    is_held_by_profile_left = true,
                },
            }
        )
        expect.equal(plan.window_ids_left_alone, {})
        expect.equal(plan.visits[1].placements[1].window_id, 41)
    end,

    missing_desktops_are_added_and_extra_ones_removed = function()
        local plan_adding = restore_plan.plan(
            arrangement_with(4, {}),
            CONFIGURATION,
            layout_with({ 3, 14 }),
            {},
            {}
        )
        expect.equal(plan_adding.desktop_count_changes, {
            { screen_uuid = "BUILTIN-UUID", desktops_to_add = 2, space_ids_to_remove = {} },
        })
        local plan_removing = restore_plan.plan(
            arrangement_with(2, {}),
            CONFIGURATION,
            layout_with({ 3, 14, 64, 163 }),
            {},
            {}
        )
        expect.equal(plan_removing.desktop_count_changes, {
            {
                screen_uuid = "BUILTIN-UUID",
                desktops_to_add = 0,
                space_ids_to_remove = { 64, 163 },
            },
        })
    end,

    a_window_saved_as_minimized_is_minimized = function()
        local record = record_on(41, 1)
        record.is_minimized = true
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
                    is_app_hidden = false,
                    is_held_by_profile_left = false,
                },
            }
        )
        expect.equal(plan.window_ids_to_minimize, { 41 })
        expect.equal(plan.visits, {})
    end,

    visits_are_ordered_by_desktop = function()
        local first, second = record_on(41, 3), record_on(42, 2)
        local plan = restore_plan.plan(
            arrangement_with(3, { first, second }),
            CONFIGURATION,
            layout_with({ 3, 14, 64 }),
            { { record = first, window_id = 41 }, { record = second, window_id = 42 } },
            {
                [41] = {
                    bundle_id = "com.apple.Safari",
                    space_id = nil,
                    is_minimized = true,
                    is_app_hidden = false,
                    is_held_by_profile_left = false,
                },
                [42] = {
                    bundle_id = "com.apple.Safari",
                    space_id = nil,
                    is_minimized = true,
                    is_app_hidden = false,
                    is_held_by_profile_left = false,
                },
            }
        )
        expect.equal(plan.visits[1].desktop_number, 2)
        expect.equal(plan.visits[2].desktop_number, 3)
    end,
}
