local expect = require("tests.expect")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local missing_windows = require("desktop_manager.core.missing_windows")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }
local EXTERNAL_FRAME = { x = 1440, y = 0, w = 1920, h = 1080 }

local CONFIGURATION = monitor_configuration.describe({
    {
        uuid = "BUILTIN-UUID",
        name = "Built-in Retina Display",
        is_builtin = true,
        frame = BUILTIN_FRAME,
    },
    { uuid = "EXTERNAL-UUID", name = "LG TV SSCR2", is_builtin = false, frame = EXTERNAL_FRAME },
}, monitor_matching.BY_COUNT)

local LAYOUT = {
    screens = {
        {
            screen_uuid = "BUILTIN-UUID",
            screen_frame = BUILTIN_FRAME,
            space_ids = { 3, 14 },
            active_space_id = 3,
        },
        {
            screen_uuid = "EXTERNAL-UUID",
            screen_frame = EXTERNAL_FRAME,
            space_ids = { 7, 8 },
            active_space_id = 7,
        },
    },
    focused_space_id = 3,
}

---@param window_id integer
---@param slot_key string|nil
---@param desktop_number integer|nil
---@return WindowRecord
local function record_on(window_id, slot_key, desktop_number)
    return {
        window_id = window_id,
        bundle_id = "com.apple.Safari",
        app_name = "Safari",
        title = tostring(window_id),
        slot_key = slot_key,
        desktop_number = desktop_number,
        unit_frame = { x = 0, y = 0, w = 1, h = 1 },
        is_out_of_sight = false,
    }
end

return {
    missing_windows_are_grouped_by_screen_and_desktop = function()
        local plan = missing_windows.plan_visits({
            record_on(41, "external 1", 2),
            record_on(42, "built-in", 2),
            record_on(43, "external 1", 2),
            record_on(44, "built-in", 1),
        }, CONFIGURATION, LAYOUT)
        expect.equal(#plan.visits, 3)
        expect.equal(plan.visits[1].screen_uuid, "BUILTIN-UUID")
        expect.equal(plan.visits[1].desktop_number, 1)
        expect.equal(plan.visits[2].desktop_number, 2)
        expect.equal(plan.visits[3].screen_uuid, "EXTERNAL-UUID")
        expect.equal(#plan.visits[3].missing_windows, 2)
        expect.equal(plan.visits[3].missing_windows[2].record.window_id, 43)
        expect.equal(plan.unplaced_records, {})
    end,

    a_desktop_beyond_the_screen_becomes_its_last_desktop = function()
        local plan =
            missing_windows.plan_visits({ record_on(41, "built-in", 5) }, CONFIGURATION, LAYOUT)
        expect.equal(plan.visits[1].desktop_number, 2)
    end,

    a_record_without_a_place_is_left_unplaced = function()
        local plan = missing_windows.plan_visits({
            record_on(41, nil, nil),
            record_on(42, "external 2", 1),
        }, CONFIGURATION, LAYOUT)
        expect.equal(plan.visits, {})
        expect.equal(#plan.unplaced_records, 2)
    end,

    the_policy_names_two_values = function()
        expect.equal(missing_window_policy.is_valid(missing_window_policy.OPEN_NEW_WINDOW), true)
        expect.equal(
            missing_window_policy.is_valid(missing_window_policy.MATCH_TITLE_OR_OPEN_NEW_WINDOW),
            true
        )
        expect.equal(missing_window_policy.is_valid("guess"), false)
    end,
}
