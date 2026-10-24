local concealment_method = require("desktop_manager.core.concealment_method")
local expect = require("tests.expect")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local reach_plan = require("desktop_manager.core.reach_plan")

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
            space_ids = { 3, 14, 64 },
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

---A window of Safari on desktop 2 of the built-in display, on its left half.
local UNSEEN_WINDOW = {
    window_id = 50,
    bundle_id = "com.apple.Safari",
    app_name = "Safari",
    title = "Reading list",
    space_id = 14,
    frame = { x = 0, y = 25, w = 720, h = 875 },
}

---@param slot_key string
---@param desktop_number integer
---@param unit_frame Rect|nil
---@return WindowMatch[]
local function matches_on(slot_key, desktop_number, unit_frame)
    return {
        {
            window_id = 50,
            record = {
                window_id = 50,
                bundle_id = "com.apple.Safari",
                app_name = "Safari",
                title = "Reading list",
                slot_key = slot_key,
                desktop_number = desktop_number,
                unit_frame = unit_frame,
                is_out_of_sight = false,
            },
        },
    }
end

---@param matches WindowMatch[]
---@return integer[]
local function select_misplaced(matches)
    return reach_plan.select_misplaced({ UNSEEN_WINDOW }, matches, CONFIGURATION, LAYOUT)
end

---@param window_id integer
---@param bundle_id string
---@param is_kept boolean
---@return SwitchCandidate
local function candidate(window_id, bundle_id, is_kept)
    return { window_id = window_id, bundle_id = bundle_id, is_in_sight = true, is_kept = is_kept }
end

return {
    an_unseen_window_off_its_recorded_desktop_is_reached = function()
        expect.equal(select_misplaced(matches_on("built-in", 3, nil)), { 50 })
        expect.equal(select_misplaced(matches_on("external 1", 2, nil)), { 50 })
    end,

    an_unseen_window_at_another_frame_is_reached = function()
        expect.equal(
            select_misplaced(matches_on("built-in", 2, { x = 0.5, y = 0, w = 0.5, h = 1 })),
            { 50 }
        )
    end,

    an_unseen_window_in_place_is_left = function()
        expect.equal(
            select_misplaced(matches_on("built-in", 2, { x = 0, y = 0, w = 0.5, h = 1 })),
            {}
        )
        expect.equal(select_misplaced(matches_on("built-in", 2, nil)), {})
    end,

    an_unseen_window_recorded_beyond_the_desktops_of_its_screen_is_reached = function()
        expect.equal(select_misplaced(matches_on("built-in", 5, nil)), { 50 })
    end,

    an_unseen_window_recorded_out_of_sight_is_left_to_the_concealment = function()
        local matches = matches_on("built-in", 3, nil)
        matches[1].record.is_out_of_sight = true
        expect.equal(select_misplaced(matches), {})
    end,

    an_unseen_window_that_the_profile_does_not_keep_is_reached = function()
        local method = concealment_method.MINIMIZE_WINDOWS
        expect.equal(
            reach_plan.select_concealed(method, { UNSEEN_WINDOW }, {
                candidate(50, "com.apple.Safari", false),
            }),
            { 50 }
        )
        expect.equal(
            reach_plan.select_concealed(method, { UNSEEN_WINDOW }, {
                candidate(50, "com.apple.Safari", true),
            }),
            {}
        )
    end,

    hiding_reaches_no_window_of_an_application_that_it_hides_whole = function()
        local method = concealment_method.HIDE_APPLICATIONS
        expect.equal(
            reach_plan.select_concealed(method, { UNSEEN_WINDOW }, {
                candidate(41, "com.apple.Safari", false),
                candidate(50, "com.apple.Safari", false),
            }),
            {}
        )
        expect.equal(
            reach_plan.select_concealed(method, { UNSEEN_WINDOW }, {
                candidate(41, "com.apple.Safari", true),
                candidate(50, "com.apple.Safari", false),
            }),
            { 50 }
        )
    end,

    an_unseen_window_moves_into_view_on_the_desktop_that_its_screen_shows = function()
        expect.equal(reach_plan.plan_moves_into_view({ UNSEEN_WINDOW }, LAYOUT), {
            moves = { { window_id = 50, space_id = 3 } },
            desktop_numbers = { [50] = 2 },
            windows_without_shown_desktop = {},
        })
    end,

    an_unseen_window_whose_screen_shows_no_desktop_gets_no_move = function()
        local window_in_full_screen = {
            window_id = 51,
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            title = "Downloads",
            space_id = 8,
            frame = EXTERNAL_FRAME,
        }
        local layout = {
            screens = {
                LAYOUT.screens[1],
                {
                    screen_uuid = "EXTERNAL-UUID",
                    screen_frame = EXTERNAL_FRAME,
                    space_ids = { 7, 8 },
                    active_space_id = 99,
                },
            },
            focused_space_id = 3,
        }
        expect.equal(
            reach_plan.plan_moves_into_view({ window_in_full_screen, UNSEEN_WINDOW }, layout),
            {
                moves = { { window_id = 50, space_id = 3 } },
                desktop_numbers = { [50] = 2 },
                windows_without_shown_desktop = { window_in_full_screen },
            }
        )
    end,

    the_windows_of_the_ids_keep_their_order_and_appear_once = function()
        local first = { window_id = 1 }
        local second = { window_id = 2 }
        local third = { window_id = 3 }
        expect.equal(
            reach_plan.keep_windows_of_ids({ first, second, third }, { 3, 1, 3 }),
            { first, third }
        )
    end,
}
