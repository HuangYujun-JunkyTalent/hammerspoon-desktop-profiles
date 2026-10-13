local arrangement_capture = require("desktop_manager.core.arrangement_capture")
local expect = require("tests.expect")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }
local LG_FRAME = { x = 1440, y = 0, w = 1872, h = 1053 }

local CONFIGURATION = monitor_configuration.describe({
    {
        uuid = "BUILTIN-UUID",
        name = "Built-in Retina Display",
        is_builtin = true,
        frame = BUILTIN_FRAME,
    },
    { uuid = "LG-UUID", name = "LG TV SSCR2", is_builtin = false, frame = LG_FRAME },
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
            screen_uuid = "LG-UUID",
            screen_frame = LG_FRAME,
            space_ids = { 649, 614 },
            active_space_id = 649,
        },
    },
    focused_space_id = 649,
}

return {
    to_unit_frame_is_relative_to_the_screen = function()
        local unit =
            arrangement_capture.to_unit_frame({ x = 720, y = 25, w = 720, h = 875 }, BUILTIN_FRAME)
        expect.equal(unit, { x = 0.5, y = 0, w = 0.5, h = 1 })
    end,

    from_unit_frame_reaches_past_the_screen_like_the_window = function()
        local unit =
            arrangement_capture.to_unit_frame({ x = 0, y = 10, w = 1440, h = 900 }, BUILTIN_FRAME)
        expect.equal(unit.y < 0 and unit.h > 1, true)
        expect.equal(
            arrangement_capture.from_unit_frame(unit, BUILTIN_FRAME),
            { x = 0, y = 10, w = 1440, h = 900 }
        )
    end,

    from_unit_frame_gives_no_frame_without_area = function()
        expect.equal(
            arrangement_capture.from_unit_frame({ x = 0.2778, y = 1, w = 0, h = 0 }, BUILTIN_FRAME),
            nil
        )
    end,

    a_frame_without_area_keeps_the_previous_frame = function()
        local previous = {
            monitor_configuration_key = "built-in + 1 external",
            monitors = {},
            windows = {
                {
                    window_id = 41,
                    bundle_id = "org.mozilla.firefox",
                    app_name = "Firefox",
                    title = "Inbox",
                    slot_key = "built-in",
                    desktop_number = 1,
                    unit_frame = { x = 0, y = 0, w = 1, h = 1 },
                    is_out_of_sight = false,
                },
            },
        }
        local observation = {
            window_id = 41,
            bundle_id = "org.mozilla.firefox",
            app_name = "Firefox",
            title = "Inbox",
            space_id = 14,
            frame = { x = 0, y = -8, w = 0, h = 0 },
            is_out_of_sight = false,
        }
        local record =
            arrangement_capture.capture(CONFIGURATION, LAYOUT, { observation }, previous).windows[1]
        expect.equal(record.desktop_number, 2)
        expect.equal(record.unit_frame, { x = 0, y = 0, w = 1, h = 1 })
    end,

    capture_records_slot_desktop_and_frame = function()
        local observation = {
            window_id = 41,
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            title = "Inbox",
            space_id = 614,
            frame = { x = 1440, y = 0, w = 936, h = 1053 },
            is_out_of_sight = false,
        }
        local arrangement = arrangement_capture.capture(CONFIGURATION, LAYOUT, { observation }, nil)
        expect.equal(arrangement.monitor_configuration_key, "built-in + 1 external")
        expect.equal(arrangement.monitors, {
            { slot_key = "built-in", desktop_count = 3 },
            { slot_key = "external 1", desktop_count = 2 },
        })
        expect.equal(arrangement.focus, { slot_key = "external 1", desktop_number = 1 })
        expect.equal(arrangement.windows[1].slot_key, "external 1")
        expect.equal(arrangement.windows[1].desktop_number, 2)
        expect.equal(arrangement.windows[1].unit_frame, { x = 0, y = 0, w = 0.5, h = 1 })
    end,

    a_window_out_of_sight_keeps_its_previous_location = function()
        local previous = {
            monitor_configuration_key = "built-in + 1 external",
            monitors = {},
            windows = {
                {
                    window_id = 41,
                    bundle_id = "com.apple.Safari",
                    app_name = "Safari",
                    title = "Inbox",
                    slot_key = "built-in",
                    desktop_number = 3,
                    unit_frame = { x = 0, y = 0, w = 1, h = 1 },
                    is_out_of_sight = false,
                },
            },
        }
        local observation = {
            window_id = 41,
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            title = "Inbox",
            space_id = nil,
            frame = nil,
            is_out_of_sight = true,
        }
        local record =
            arrangement_capture.capture(CONFIGURATION, LAYOUT, { observation }, previous).windows[1]
        expect.equal(record.slot_key, "built-in")
        expect.equal(record.desktop_number, 3)
        expect.equal(record.unit_frame, { x = 0, y = 0, w = 1, h = 1 })
        expect.equal(record.is_out_of_sight, true)
    end,

    a_window_on_an_unknown_space_without_history_has_no_location = function()
        local observation = {
            window_id = 77,
            bundle_id = "com.apple.Notes",
            app_name = "Notes",
            title = "List",
            space_id = 9999,
            frame = { x = 0, y = 0, w = 10, h = 10 },
            is_out_of_sight = false,
        }
        local record =
            arrangement_capture.capture(CONFIGURATION, LAYOUT, { observation }, nil).windows[1]
        expect.equal(record.slot_key, nil)
        expect.equal(record.desktop_number, nil)
    end,
}
