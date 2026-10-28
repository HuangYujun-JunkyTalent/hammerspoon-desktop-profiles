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

local INBOX_RECORD = {
    window_id = 41,
    bundle_id = "com.apple.Safari",
    app_name = "Safari",
    title = "Inbox",
    slot_key = "built-in",
    desktop_number = 3,
    unit_frame = { x = 0, y = 0, w = 1, h = 1 },
    is_out_of_sight = false,
}

return {
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
            { slot_key = "built-in", desktop_count = 3, shown_desktop_number = 1 },
            { slot_key = "external 1", desktop_count = 2, shown_desktop_number = 1 },
        })
        expect.equal(arrangement.focused_slot_key, "external 1")
        expect.equal(arrangement.windows[1].slot_key, "external 1")
        expect.equal(arrangement.windows[1].desktop_number, 2)
        expect.equal(arrangement.windows[1].unit_frame, { x = 0, y = 0, w = 0.5, h = 1 })
    end,

    a_screen_in_full_screen_keeps_its_previous_shown_desktop = function()
        local layout = {
            screens = {
                {
                    screen_uuid = "BUILTIN-UUID",
                    screen_frame = BUILTIN_FRAME,
                    space_ids = { 3, 14, 64 },
                    active_space_id = 900,
                },
                {
                    screen_uuid = "LG-UUID",
                    screen_frame = LG_FRAME,
                    space_ids = { 649, 614 },
                    active_space_id = 614,
                },
            },
            focused_space_id = 900,
        }
        local previous = {
            monitor_configuration_key = "built-in + 1 external",
            monitors = {
                { slot_key = "built-in", desktop_count = 3, shown_desktop_number = 2 },
                { slot_key = "external 1", desktop_count = 2, shown_desktop_number = 1 },
            },
            focused_slot_key = "external 1",
            windows = {},
        }
        local arrangement = arrangement_capture.capture(CONFIGURATION, layout, {}, previous)
        expect.equal(arrangement.monitors, {
            { slot_key = "built-in", desktop_count = 3, shown_desktop_number = 2 },
            { slot_key = "external 1", desktop_count = 2, shown_desktop_number = 2 },
        })
        expect.equal(arrangement.focused_slot_key, "built-in")
    end,

    a_screen_whose_desktops_macos_does_not_list_keeps_its_previous_record = function()
        local layout = { screens = { LAYOUT.screens[1] }, focused_space_id = 3 }
        local previous = {
            monitor_configuration_key = "built-in + 1 external",
            monitors = {
                { slot_key = "built-in", desktop_count = 4, shown_desktop_number = 2 },
                { slot_key = "external 1", desktop_count = 2, shown_desktop_number = 2 },
            },
            focused_slot_key = "built-in",
            windows = {},
        }
        expect.equal(arrangement_capture.capture(CONFIGURATION, layout, {}, previous).monitors, {
            { slot_key = "built-in", desktop_count = 3, shown_desktop_number = 1 },
            { slot_key = "external 1", desktop_count = 2, shown_desktop_number = 2 },
        })
        expect.equal(arrangement_capture.capture(CONFIGURATION, layout, {}, nil).monitors, {
            { slot_key = "built-in", desktop_count = 3, shown_desktop_number = 1 },
        })
    end,

    a_focus_on_no_screen_keeps_the_previous_screen_of_the_focus = function()
        local layout = {
            screens = LAYOUT.screens,
            focused_space_id = nil,
        }
        local previous = {
            monitor_configuration_key = "built-in + 1 external",
            monitors = {},
            focused_slot_key = "built-in",
            windows = {},
        }
        expect.equal(
            arrangement_capture.capture(CONFIGURATION, layout, {}, previous).focused_slot_key,
            "built-in"
        )
        expect.equal(
            arrangement_capture.capture(CONFIGURATION, layout, {}, nil).focused_slot_key,
            nil
        )
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

    an_unseen_window_keeps_the_recorded_title_when_macos_gives_none = function()
        local server_window = {
            window_id = 41,
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            title = "",
            space_id = 64,
            frame = { x = 0, y = 25, w = 600, h = 400 },
        }
        expect.equal(arrangement_capture.observe_server_window(server_window, INBOX_RECORD), {
            window_id = 41,
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            title = "Inbox",
            space_id = 64,
            frame = { x = 0, y = 25, w = 600, h = 400 },
            is_out_of_sight = false,
        })
        expect.equal(arrangement_capture.observe_server_window(server_window, nil).title, "")
    end,

    an_unlisted_record_keeps_its_title_and_sight_on_the_desktop_that_macos_lists = function()
        expect.equal(arrangement_capture.observe_unlisted_record(INBOX_RECORD, 64), {
            window_id = 41,
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            title = "Inbox",
            space_id = 64,
            is_out_of_sight = false,
        })
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

    a_change_of_desktop_records_the_desktops_and_keeps_the_windows = function()
        local arrangement = arrangement_capture.capture(CONFIGURATION, LAYOUT, {}, nil)
        arrangement.windows = { INBOX_RECORD }
        expect.equal(
            arrangement_capture.with_desktops_in_view(arrangement, CONFIGURATION, LAYOUT),
            nil
        )
        local layout = {
            screens = {
                {
                    screen_uuid = "BUILTIN-UUID",
                    screen_frame = BUILTIN_FRAME,
                    space_ids = { 3, 14, 64, 65 },
                    active_space_id = 14,
                },
                LAYOUT.screens[2],
            },
            focused_space_id = 14,
        }
        local updated = expect.present(
            arrangement_capture.with_desktops_in_view(arrangement, CONFIGURATION, layout),
            "the arrangement of the new desktops"
        )
        expect.equal(updated.monitors[1].shown_desktop_number, 2)
        expect.equal(updated.monitors[1].desktop_count, 4)
        expect.equal(updated.monitors[2], arrangement.monitors[2])
        expect.equal(updated.focused_slot_key, CONFIGURATION.slots[1].slot_key)
        expect.equal(updated.windows, { INBOX_RECORD })
        expect.equal(arrangement.monitors[1].shown_desktop_number, 1)
    end,
}
