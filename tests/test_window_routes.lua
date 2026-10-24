local expect = require("tests.expect")
local fake_worlds = require("tests.fake_worlds")
local window_routes = require("desktop_manager.core.window_routes")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }
local EXTERNAL_FRAME = { x = 1440, y = 0, w = 1920, h = 1080 }
local LEFT_HALF = { x = 0, y = 0, w = 0.5, h = 1 }
local LEFT_HALF_OF_BUILTIN = { x = 0, y = 25, w = 720, h = 875 }
local ELSEWHERE = { x = 300, y = 200, w = 600, h = 400 }

---The built-in display shows desktop 1 of 3, and the external monitor desktop 1 of 2.
---@return DesktopLayout
local function build_layout()
    return {
        screens = {
            fake_worlds.describe_screen_desktops("BUILTIN-UUID", BUILTIN_FRAME, { 3, 14, 64 }),
            fake_worlds.describe_screen_desktops("EXTERNAL-UUID", EXTERNAL_FRAME, { 7, 8 }),
        },
        focused_space_id = 3,
    }
end

---@param desktop_number integer
---@param unit_frame Rect|nil
---@return WindowPlacement
local function placement_on_builtin(desktop_number, unit_frame)
    return {
        window_id = 41,
        screen_uuid = "BUILTIN-UUID",
        slot_key = "built-in",
        desktop_number = desktop_number,
        unit_frame = unit_frame,
    }
end

---@param space_ids integer[]
---@param frame Rect|nil
---@return WindowLocation
local function location_of(space_ids, frame)
    return { space_ids = space_ids, frame = frame }
end

return {
    a_window_on_its_desktop_at_its_frame_needs_no_route = function()
        local route, reason = window_routes.plan(
            placement_on_builtin(2, LEFT_HALF),
            location_of({ 14 }, { x = 1, y = 26, w = 719, h = 874 }),
            build_layout()
        )
        expect.equal(route, nil)
        expect.equal(reason, nil)
    end,

    a_window_in_view_at_another_frame_gets_its_frame_alone = function()
        local route = window_routes.plan(
            placement_on_builtin(1, LEFT_HALF),
            location_of({ 3 }, ELSEWHERE),
            build_layout()
        )
        expect.equal(route, {
            window_id = 41,
            view_space_id = nil,
            target_frame = LEFT_HALF_OF_BUILTIN,
            target_space_id = 3,
            target_screen_uuid = "BUILTIN-UUID",
            is_across_screens = false,
        })
    end,

    a_window_out_of_view_at_another_frame_goes_into_view_first = function()
        local route = window_routes.plan(
            placement_on_builtin(2, LEFT_HALF),
            location_of({ 14 }, ELSEWHERE),
            build_layout()
        )
        expect.equal(route.view_space_id, 3)
        expect.equal(route.target_frame, LEFT_HALF_OF_BUILTIN)
        expect.equal(route.target_space_id, 14)
    end,

    a_window_out_of_view_at_its_frame_moves_by_its_id_alone = function()
        local route = window_routes.plan(
            placement_on_builtin(2, LEFT_HALF),
            location_of({ 64 }, LEFT_HALF_OF_BUILTIN),
            build_layout()
        )
        expect.equal(route.view_space_id, nil)
        expect.equal(route.target_frame, nil)
        expect.equal(route.target_space_id, 14)
        expect.equal(route.is_across_screens, false)
    end,

    a_window_on_another_screen_goes_by_its_frame_and_then_by_its_id = function()
        local route = window_routes.plan(
            placement_on_builtin(2, LEFT_HALF),
            location_of({ 7 }, { x = 1440, y = 0, w = 720, h = 875 }),
            build_layout()
        )
        expect.equal(route.view_space_id, nil)
        expect.equal(route.target_frame, LEFT_HALF_OF_BUILTIN)
        expect.equal(route.target_space_id, 14)
        expect.equal(route.is_across_screens, true)
    end,

    a_window_out_of_view_on_another_screen_goes_into_view_first = function()
        local route = window_routes.plan(
            placement_on_builtin(2, LEFT_HALF),
            location_of({ 8 }, ELSEWHERE),
            build_layout()
        )
        expect.equal(route.view_space_id, 7)
        expect.equal(route.is_across_screens, true)
    end,

    a_window_whose_frame_is_unknown_gets_its_frame = function()
        local route = window_routes.plan(
            placement_on_builtin(1, LEFT_HALF),
            location_of({ 3 }, nil),
            build_layout()
        )
        expect.equal(route.target_frame, LEFT_HALF_OF_BUILTIN)
    end,

    a_window_on_every_desktop_or_on_none_stays_with_a_reason = function()
        local placement = placement_on_builtin(2, LEFT_HALF)
        local route, reason =
            window_routes.plan(placement, location_of({ 3, 14 }, ELSEWHERE), build_layout())
        expect.equal(route, nil)
        expect.equal(reason, "is on every desktop, and stays")
        route, reason = window_routes.plan(placement, location_of({}, nil), build_layout())
        expect.equal(route, nil)
        expect.equal(reason, "has no desktop now")
    end,

    a_window_in_full_screen_stays_with_a_reason = function()
        local _, reason = window_routes.plan(
            placement_on_builtin(2, LEFT_HALF),
            location_of({ 900 }, ELSEWHERE),
            build_layout()
        )
        expect.equal(reason, "is in full screen, and stays")
    end,

    a_window_without_a_recorded_frame_stays_on_its_screen_with_a_reason = function()
        local route, reason = window_routes.plan(
            placement_on_builtin(2, nil),
            location_of({ 7 }, ELSEWHERE),
            build_layout()
        )
        expect.equal(route, nil)
        expect.equal(reason, "has no recorded frame for built-in, and stays")
        route, reason = window_routes.plan(
            placement_on_builtin(2, { x = 0.2, y = 1, w = 0, h = 0 }),
            location_of({ 7 }, ELSEWHERE),
            build_layout()
        )
        expect.equal(route, nil)
        expect.equal(reason, "has no recorded frame for built-in, and stays")
        route = window_routes.plan(
            placement_on_builtin(2, nil),
            location_of({ 64 }, ELSEWHERE),
            build_layout()
        )
        expect.equal(route.target_frame, nil)
        expect.equal(route.target_space_id, 14)
    end,

    a_missing_desktop_is_reported = function()
        local route, reason = window_routes.plan(
            placement_on_builtin(5, LEFT_HALF),
            location_of({ 3 }, ELSEWHERE),
            build_layout()
        )
        expect.equal(route, nil)
        expect.equal(reason, "has no desktop 5 on built-in")
    end,

    no_frame_is_set_on_a_screen_that_shows_a_window_in_full_screen = function()
        local layout = build_layout()
        layout.screens[1].active_space_id = 900
        local _, reason = window_routes.plan(
            placement_on_builtin(2, LEFT_HALF),
            location_of({ 14 }, ELSEWHERE),
            layout
        )
        expect.equal(
            reason,
            "is out of view while its screen shows a window in full screen, and stays"
        )
        _, reason = window_routes.plan(
            placement_on_builtin(2, LEFT_HALF),
            location_of({ 7 }, ELSEWHERE),
            layout
        )
        expect.equal(reason, "stays off built-in, which shows a window in full screen")
    end,
}
