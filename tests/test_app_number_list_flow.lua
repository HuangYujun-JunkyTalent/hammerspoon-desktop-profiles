local app_switcher = require("desktop_manager.macos.app_switcher")
local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local fake_worlds = require("tests.fake_worlds")
local list_layout = require("desktop_manager.core.list_layout")
local list_sizing = require("desktop_manager.core.list_sizing")
local preview_method = require("desktop_manager.core.preview_method")
local profile_state = require("desktop_manager.core.profile_state")
local retained_timers = require("desktop_manager.macos.retained_timers")
local title_overflow = require("desktop_manager.core.title_overflow")

return {
    a_number_brings_its_application_and_the_next_press_its_next_window = function()
        local world, controller = controller_world.start_world()
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local entries = profile_state.profile_or_default(controller.state, 1).app_numbers
        expect.equal(entries[1].bundle_id, "com.apple.Safari")
        expect.equal(entries[2].bundle_id, "com.microsoft.Word")
        world.app_hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.displays[1].active_space_id, 14)
        world.app_hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, news.id)
        expect.equal(world.displays[1].active_space_id, 3)
        world.app_hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.mission_control_actions, { "show 14", "show 3", "show 14" })
        expect.equal(world.key_strokes, {})
        local shown, visible_count = controller_world.read_busy_messages(world)
        expect.equal(shown, {
            "Arranging Profile 1… please wait",
            "Showing desktop 2 of built-in… please wait",
            "Showing desktop 1 of built-in… please wait",
            "Showing desktop 2 of built-in… please wait",
        })
        expect.equal(visible_count, 0)
        expect.equal(controller.is_press_running, false)
    end,

    a_press_of_the_list_during_a_switch_is_refused = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.app_hotkeys["2"]()
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        expect.equal(world.notifications, {})
        local shown, visible_count = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Arranging Profile 1… please wait")
        expect.equal(visible_count, 1)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(controller.is_switch_or_restore_running, false)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.displays[1].active_space_id, 3)
    end,

    a_switch_during_a_press_of_the_list_is_refused = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.app_hotkeys["2"]()
        expect.equal(controller.is_press_running, true)
        world.hotkeys["2"]()
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(controller.is_press_running, false)
        expect.equal(world.focused_window_id, 41)
    end,

    a_deactivation_during_a_press_of_the_list_is_refused = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.app_hotkeys["2"]()
        expect.equal(controller.is_press_running, true)
        local alert_count = #world.alerts
        world.hotkeys["1"]()
        world.hotkeys["0"]()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "deactivate", profile = "1" }
        )
        expect.equal(#world.alerts, alert_count + 3)
        for index = alert_count + 1, #world.alerts do
            expect.equal(world.alerts[index], "Desktop Manager is still switching")
        end
        expect.equal(controller.state.active_profile_number, 1)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(controller.is_press_running, false)
    end,

    a_clear_during_a_press_of_the_list_is_refused = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.app_hotkeys["2"]()
        expect.equal(controller.is_press_running, true)
        world.alert_button = "Clear"
        world.hotkey_by_shortcut["ctrl+alt+cmd 1"]()
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        expect.equal(profile_state.has_arrangements(controller.state, 1), true)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(profile_state.has_arrangements(controller.state, 1), true)
        expect.equal(controller.is_press_running, false)
    end,

    a_monitor_change_during_a_press_of_the_list_is_restored_after_the_press = function()
        local timing = fake_worlds.create_default_timing()
        timing.screen_settle_seconds = 0.2
        local world, controller = controller_world.start_world({ timing = timing })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.app_hotkeys["2"]()
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(0.3)
        expect.equal(controller.is_press_running, true)
        expect.equal(controller.is_switch_or_restore_running, false)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 14" })
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(controller_world.read_busy_messages(world), {
            "Arranging Profile 1… please wait",
            "Showing desktop 2 of built-in… please wait",
            "Monitors changed, waiting for macOS… please wait",
            "Arranging Profile 1 for built-in… please wait",
        })
        expect.equal(controller.is_switch_or_restore_running, false)
        expect.equal(controller.are_saves_suspended, false)
        controller_world.expect_frame_near(
            world.windows[42].frame,
            { x = 756, y = 25, w = 756, h = 957 }
        )
    end,

    a_desktop_that_mission_control_does_not_show_is_reported = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.ignores_desktop_presses = true
        world.app_hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local message = "Mission Control did not show desktop 2 of Built-in Retina Display"
            .. " within 5 seconds, after one opening and two presses"
            .. " (1 problems in the Hammerspoon console)"
        expect.equal(world.alerts[#world.alerts], message)
        expect.equal(world.notifications, { message })
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.focused_window_id, nil)
    end,

    a_held_press_shows_the_list_and_the_release_goes_to_the_selection = function()
        local world = controller_world.start_world({ list_layout = list_layout.ROWS })
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        expect.equal(world.read_overlay(), {
            " 1   Safari",
            ">Inbox",
            " News",
            " 2   Microsoft Word",
            " Draft.docx",
        })
        expect.equal(world.read_overlay_images(), {
            "icon com.apple.Safari",
            "icon com.apple.Safari",
            "icon com.apple.Safari",
            "icon com.microsoft.Word",
            "icon com.microsoft.Word",
        })
        world.app_hotkeys["1"]()
        expect.equal(world.read_overlay()[3], ">News")
        world.app_hotkeys["7"]()
        expect.equal(world.key_strokes, {})
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.read_overlay(), nil)
        expect.equal(world.focused_window_id, news.id)
    end,

    a_press_of_another_number_selects_its_application_and_escape_closes_the_list = function()
        local world = controller_world.start_world({ list_layout = list_layout.ROWS })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        expect.equal(world.read_overlay()[2], ">Draft.docx")
        world.app_hotkeys["2"]()
        expect.equal(world.read_overlay()[4], ">Inbox")
        world.press_escape()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.read_overlay(), nil)
        expect.equal(world.focused_window_id, nil)
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, nil)
    end,

    a_preview_that_comes_between_the_release_and_the_close_draws_nothing = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["2"]()
        -- Hammerspoon may handle the release before a line of the helper, and both before the
        -- timers that they defer. Releasing during the decode of the first preview gives that
        -- order: the close of the list is deferred before the redraw of the preview.
        local image_from_url = _G.hs.image.imageFromURL
        _G.hs.image.imageFromURL = function(url)
            if world.held_modifiers.ctrl then
                world.release_modifiers()
            end
            return image_from_url(url)
        end
        local canvas = world.overlay
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(canvas.is_deleted, true)
        expect.equal(world.held_modifiers, {})
    end,

    closing_the_list_deletes_its_canvas_which_then_takes_no_call = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["2"]()
        local canvas = world.overlay
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(canvas.is_deleted, true)
        expect.equal(pcall(canvas.replaceElements, canvas, {}), false)
    end,

    the_setting_for_snapshots_shows_blurred_previews_and_icons_without_them = function()
        local world = controller_world.start_world({
            preview_method = preview_method.BLURRED_SNAPSHOTS,
            preview_blur = 2,
            list_layout = list_layout.ROWS,
            list_sizing = list_sizing.FIXED,
            preview_size = { w = 0.04, h = 0.04 },
        })
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.minimize_window(42)
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(1)
        expect.equal(world.read_overlay_images(), {
            "icon com.apple.Safari",
            "blurred 41",
            "blurred " .. news.id,
            "icon com.microsoft.Word",
            "icon com.microsoft.Word",
        })
        expect.equal(world.rendered_sizes[41], { w = 58, h = 29 })
    end,

    the_blur_setting_sets_the_size_of_the_rendering = function()
        local world = controller_world.start_world({
            preview_method = preview_method.BLURRED_SNAPSHOTS,
            preview_blur = 4,
            list_sizing = list_sizing.FIXED,
            preview_size = { w = 0.04, h = 0.04 },
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(1)
        expect.equal(world.rendered_sizes[41], { w = 29, h = 14 })
    end,

    the_settings_of_size_set_the_previews_and_the_fonts_of_the_list = function()
        local world = controller_world.start_world({
            preview_method = preview_method.BLURRED_SNAPSHOTS,
            preview_blur = 1,
            preview_size = { w = 0.05, h = 0.05 },
            list_font_size = 0.02,
            list_layout = list_layout.ROWS,
            list_sizing = list_sizing.FIXED,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(1)
        expect.equal(world.rendered_sizes[41], { w = 144, h = 72 })
        local preview_frames, text_sizes = {}, {}
        for _, element in ipairs(world.overlay.elements) do
            if element.type == "image" and element.image.source:match("^blurred") then
                table.insert(preview_frames, { w = element.frame.w, h = element.frame.h })
            elseif element.type == "text" then
                table.insert(text_sizes, element.textSize)
            end
        end
        expect.equal(preview_frames[1], { w = 72, h = 43.75 })
        expect.equal(text_sizes, { 19.5, 17.5, 19.5, 17.5 })
    end,

    the_columns_show_each_application_with_its_windows_under_it = function()
        local world = controller_world.start_world()
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.app_hotkeys["1"]()
        expect.equal(world.read_overlay(), {
            " 1  Safari",
            " Inbox",
            ">News",
            " 2  Microsoft Word",
            " Draft.docx",
        })
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, news.id)
    end,

    a_title_that_starts_with_blanks_keeps_them_in_the_rows_and_the_columns = function()
        for _, layout in ipairs({ list_layout.ROWS, list_layout.COLUMNS }) do
            local world = controller_world.start_world({ list_layout = layout })
            world.create_window("com.apple.Safari", "  Indented")
            world.hotkeys["1"]()
            world.advance(controller_world.SETTLE_SECONDS)
            world.held_modifiers = { ctrl = true, alt = true }
            world.app_hotkeys["1"]()
            expect.equal({ layout, world.read_overlay()[3] }, { layout, "   Indented" })
            world.release_modifiers()
            world.advance(controller_world.SETTLE_SECONDS)
        end
    end,

    the_columns_per_display_name_each_display_above_its_columns = function()
        local world =
            controller_world.start_world({ list_layout = list_layout.COLUMNS_PER_DISPLAY })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        expect.equal(world.read_overlay(), {
            " Built-in Retina Display",
            " 1  Microsoft Word",
            ">Draft.docx",
            " 2  Safari",
            " Inbox",
        })
    end,

    a_list_too_tall_for_the_screen_shrinks_to_fit = function()
        local world = controller_world.start_world({ preview_size = { w = 0.1, h = 0.3 } })
        for index = 1, 6 do
            world.create_window("com.apple.Safari", "Tab " .. index)
        end
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        local frame = world.overlay.current_frame
        expect.equal(frame.h <= 0.9 * 875 + 0.5, true)
        expect.equal(frame.y >= 25, true)
    end,

    filling_the_screen_grows_a_short_list_and_fixed_sizes_keep_the_settings = function()
        local function read_first_preview_width(setting_changes)
            local world = controller_world.start_world(setting_changes)
            world.hotkeys["1"]()
            world.advance(controller_world.SETTLE_SECONDS)
            world.held_modifiers = { ctrl = true, alt = true }
            world.app_hotkeys["1"]()
            world.advance(1)
            for _, element in ipairs(world.overlay.elements) do
                if element.type == "image" and element.image.source:match("^blurred") then
                    return element.frame.w, world.overlay.current_frame
                end
            end
            error("the list shows no image as large as a preview")
        end
        local filled_width, filled_frame = read_first_preview_width({})
        expect.equal(filled_width > 144, true)
        expect.equal(filled_width <= 2.5 * 144, true)
        expect.equal(filled_frame.w <= 0.95 * 1440 + 0.5, true)
        expect.equal(filled_frame.h <= 0.9 * 875 + 0.5, true)
        local fixed_width = read_first_preview_width({ list_sizing = list_sizing.FIXED })
        expect.equal(fixed_width, 144)
    end,

    many_columns_fold_into_two_lines = function()
        local world = controller_world.start_world()
        for index = 1, 7 do
            local bundle_id = "com.example.App" .. index
            world.applications[bundle_id] = {
                name = "App " .. index,
                is_running = true,
                is_hidden = false,
                launch_titles = {},
            }
            world.create_window(bundle_id, "Window " .. index)
        end
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        local header_tops = {}
        for _, element in ipairs(world.overlay.elements) do
            if element.type == "text" and element.textFont == "Helvetica-Bold" then
                header_tops[element.frame.y] = (header_tops[element.frame.y] or 0) + 1
            end
        end
        local counts = {}
        for _, count in pairs(header_tops) do
            table.insert(counts, count)
        end
        table.sort(counts)
        expect.equal(counts, { 4, 5 })
    end,

    a_wrapping_title_flows_over_the_lines_it_needs_up_to_the_limit = function()
        local long_title = string.rep("word ", 12)
        local function read_title_element(line_limit)
            local world = controller_world.start_world({
                list_sizing = list_sizing.FIXED,
                list_font_size = 0.016,
                title_overflow = title_overflow.WRAP,
                title_line_count = line_limit,
            })
            world.create_window("com.apple.Safari", long_title)
            world.hotkeys["1"]()
            world.advance(controller_world.SETTLE_SECONDS)
            world.held_modifiers = { ctrl = true, alt = true }
            world.app_hotkeys["1"]()
            for _, element in ipairs(world.overlay.elements) do
                if element.type == "text" and element.text:match("^word") then
                    return element
                end
            end
            error("the list shows no long title")
        end
        local three_lines = read_title_element(3)
        expect.equal(three_lines.frame.h, 60)
        expect.equal(three_lines.textLineBreak, "wordWrap")
        local two_lines = read_title_element(2)
        expect.equal(two_lines.frame.h, 40)
        expect.present(two_lines.text:match("…$"), "an ellipsis at the end of the title")
    end,

    the_selected_title_scrolls_and_the_scrolling_stops_with_the_list = function()
        local long_title = "A very long title of a window that does not fit its column at all"
        local world = controller_world.start_world({
            list_sizing = list_sizing.FIXED,
            title_overflow = title_overflow.SCROLL,
        })
        local long_window = world.create_window("com.apple.Safari", long_title)
        world.create_window("com.apple.Safari", "Another very long title that the list shortens")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local timers_before = retained_timers.count_running()
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.app_hotkeys["1"]()
        local function find_text(prefix)
            for _, element in ipairs(world.overlay.elements) do
                if element.type == "text" and element.text:sub(1, #prefix) == prefix then
                    return element
                end
            end
            error("the list on the screen has no text that starts with " .. prefix)
        end
        expect.equal(world.read_overlay()[3]:sub(1, 1), ">")
        local scrolling = find_text("A very")
        expect.equal(scrolling.text:match("…$"), nil)
        expect.present(
            find_text("Another").text:match("…$"),
            "an ellipsis at the end of the title"
        )
        local first_line = world.read_overlay()[3]
        world.advance(2)
        local later_line = world.read_overlay()[3]
        expect.equal(later_line:sub(1, 1), ">")
        expect.equal(later_line ~= first_line, true)
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, long_window.id)
        expect.equal(retained_timers.count_running(), timers_before)
    end,

    the_list_starts_the_helper_after_drawing_while_numbers_are_pressed = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local snapshots_before = world.snapshot_count
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(0.04)
        expect.equal(#world.helpers, 0)
        world.app_hotkeys["1"]()
        world.advance(0.02)
        expect.equal(#world.helpers, 1)
        world.app_hotkeys["2"]()
        world.advance(1)
        expect.equal(world.snapshot_count, snapshots_before + 2)
    end,

    the_previews_of_one_chunk_of_the_helper_give_the_list_one_redraw = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.gives_helper_lines_at_once = true
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(0.26)
        local redraws_before = world.overlay.replace_count
        world.advance(0.1)
        expect.equal(world.overlay.replace_count, redraws_before + 1)
        expect.equal(world.read_overlay_images(), {
            "icon com.microsoft.Word",
            "blurred 42",
            "icon com.apple.Safari",
            "blurred 41",
        })
    end,

    closing_the_list_terminates_its_helper = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local snapshots_before = world.snapshot_count
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(0.26)
        world.press_escape()
        world.advance(1)
        expect.equal(world.helpers[1].is_terminated, true)
        expect.equal(world.snapshot_count, snapshots_before + 1)
    end,

    a_slow_snapshot_stops_the_snapshots_until_a_reload = function()
        local world =
            controller_world.start_world({ preview_method = preview_method.BLURRED_SNAPSHOTS })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.snapshot_seconds = 1
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(2)
        expect.equal(world.snapshot_count, 1)
        expect.equal(world.helpers[1].is_terminated, true)
        expect.equal(world.read_overlay_images(), {
            "icon com.microsoft.Word",
            "icon com.microsoft.Word",
            "icon com.apple.Safari",
            "icon com.apple.Safari",
        })
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(2)
        expect.equal(world.snapshot_count, 1)
        expect.equal(#world.helpers, 1)
    end,

    a_number_reaches_a_window_that_another_profile_recorded = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, true)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "5", app = "Safari" }
        )
        world.app_hotkeys["5"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.focused_window_id, 41)
    end,

    a_number_of_an_application_without_a_window_opens_one = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "4", app = "com.microsoft.Word" }
        )
        world.app_hotkeys["4"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local opened = expect.present(
            controller_world.find_window_titled(world, "Document1"),
            "the window titled Document1"
        )
        expect.equal(world.focused_window_id, opened.id)
    end,

    opening_a_window_for_a_number_shows_a_message = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "4", app = "com.microsoft.Word" }
        )
        world.app_hotkeys["4"]()
        local shown, visible_while_opening = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Opening a window of Microsoft Word… please wait")
        expect.equal(visible_while_opening, 1)
        expect.equal(controller.is_press_running, true)
        world.advance(controller_world.SETTLE_SECONDS)
        local _, visible_count = controller_world.read_busy_messages(world)
        expect.equal(visible_count, 0)
        expect.equal(controller.is_press_running, false)
        expect.equal(
            world.focused_window_id,
            controller_world.find_window_titled(world, "Document1").id
        )
    end,

    a_number_without_a_window_during_a_switch_keeps_the_message_of_the_switch = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(42)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "4", app = "com.microsoft.Word" }
        )
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.app_hotkeys["4"]()
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        expect.equal(world.notifications, {})
        local shown, visible_count = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Arranging Profile 1… please wait")
        expect.equal(visible_count, 1)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller_world.find_window_titled(world, "Document1"), nil)
    end,

    a_number_without_an_application_passes_its_keys_through = function()
        local world = controller_world.start_world()
        world.app_hotkeys["7"]()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.app_hotkeys["7"]()
        expect.equal(world.key_strokes, { "ctrl+alt+7", "ctrl+alt+7" })
        expect.equal(world.hotkey_events, {
            "disable ctrl+alt 7",
            "enable ctrl+alt 7",
            "disable ctrl+alt 7",
            "enable ctrl+alt 7",
        })
    end,

    a_number_chosen_by_the_user_survives_the_updates_and_returns_to_the_default = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "1", app = "Microsoft Word" }
        )
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local entries = profile_state.profile_or_default(controller.state, 1).app_numbers
        expect.equal(entries[1].bundle_id, "com.microsoft.Word")
        expect.equal(entries[1].is_chosen_by_user, true)
        expect.equal(entries[2].bundle_id, "com.apple.Safari")
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "release-app-number", number = "1" }
        )
        entries = profile_state.profile_or_default(controller.state, 1).app_numbers
        expect.equal(entries[1].bundle_id, "com.microsoft.Word")
        expect.equal(entries[1].is_chosen_by_user, false)
        expect.equal(entries[1].number, 1)
    end,

    profile_0_numbers_the_open_windows_while_no_profile_is_active = function()
        local world, controller = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        local entries = profile_state.profile_or_default(controller.state, 0).app_numbers
        expect.equal(entries[1].bundle_id, "com.microsoft.Word")
        expect.equal(entries[2].bundle_id, "com.apple.Safari")
        expect.equal(
            profile_state.find_arrangement(
                controller.state,
                0,
                controller_world.MONITOR_CONFIGURATION_KEY
            ),
            nil
        )
        local menu_items = {}
        for _, item in ipairs(world.menu_builder()) do
            if item.title == "Application numbers" then
                menu_items = item.menu
            end
        end
        expect.equal(menu_items[1].title, "1  Microsoft Word")
        world.app_hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
        expect.equal(controller.state.active_profile_number, nil)
    end,

    deactivating_a_profile_gives_profile_0_its_numbers_at_once = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        controller.state = profile_state.with_app_numbers(controller.state, 0, {})
        world.hotkeys["0"]()
        local entries = profile_state.profile_or_default(controller.state, 0).app_numbers
        expect.equal(#entries, 2)
    end,

    a_number_chosen_while_no_profile_is_active_goes_to_profile_0 = function()
        local world, controller = controller_world.start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "5", app = "Safari" }
        )
        expect.equal(world.alerts[#world.alerts], "Safari is number 5 in Profile 0")
        expect.equal(world.notifications, {})
        world.app_hotkeys["5"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
        expect.equal(profile_state.profile_or_default(controller.state, 1).app_numbers, {})
    end,

    control_option_0_returns_every_number_of_the_active_profile_to_the_default = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local defaults = profile_state.profile_or_default(controller.state, 1).app_numbers
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "7", app = "Safari" }
        )
        world.app_hotkeys["0"]()
        expect.equal(profile_state.profile_or_default(controller.state, 1).app_numbers, defaults)
        expect.equal(world.alerts[#world.alerts], "Profile 1 has the default application numbers")
    end,

    control_option_0_returns_every_number_of_profile_0_to_the_default = function()
        local world, controller = controller_world.start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "7", app = "Microsoft Word" }
        )
        world.app_hotkeys["0"]()
        expect.equal(profile_state.profile_or_default(controller.state, 0).app_numbers, {
            {
                number = 1,
                bundle_id = "com.microsoft.Word",
                app_name = "Microsoft Word",
                is_chosen_by_user = false,
            },
            {
                number = 2,
                bundle_id = "com.apple.Safari",
                app_name = "Safari",
                is_chosen_by_user = false,
            },
        })
        expect.equal(world.alerts[#world.alerts], "Profile 0 has the default application numbers")
    end,

    a_url_returns_every_number_to_the_default = function()
        local world, controller = controller_world.start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "7", app = "Microsoft Word" }
        )
        world.url_handlers["desktop-manager"]("desktop-manager", { action = "reset-app-numbers" })
        local entries = profile_state.profile_or_default(controller.state, 0).app_numbers
        expect.equal(entries[1].bundle_id, "com.microsoft.Word")
        expect.equal(entries[1].number, 1)
        expect.equal(entries[1].is_chosen_by_user, false)
        expect.equal(world.alerts[#world.alerts], "Profile 0 has the default application numbers")
    end,

    control_option_0_does_nothing_while_the_list_shows = function()
        local world, controller = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "7", app = "Safari" }
        )
        local chosen = profile_state.profile_or_default(controller.state, 1).app_numbers
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["7"]()
        world.app_hotkeys["0"]()
        expect.equal(profile_state.profile_or_default(controller.state, 1).app_numbers, chosen)
        expect.equal(world.overlay.is_visible, true)
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
    end,

    numbering_an_application_that_is_not_running_is_reported = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "3", app = "Notes" }
        )
        expect.equal(world.notifications, { 'No running application is named "Notes"' })
    end,

    a_number_without_a_selected_window_passes_the_recorded_window_for_the_focus = function()
        local world = controller_world.start_bounce_world()
        local letter = world.create_unseen_window("com.microsoft.Word", "Letter.docx", 8)
        local shown = {}
        local context = {
            show_space = function(space_id, _, _, chosen_window)
                table.insert(shown, { space_id = space_id, chosen_window = chosen_window })
            end,
        }
        local entry = { number = 1, bundle_id = "com.microsoft.Word", app_name = "Microsoft Word" }
        app_switcher.switch_to_selection(entry, nil, { letter.id }, context, function() end)
        expect.equal(shown, {
            {
                space_id = 8,
                chosen_window = { bundle_id = "com.microsoft.Word", window_id = letter.id },
            },
        })
    end,

    the_numbered_list_holds_a_window_on_a_desktop_not_visited = function()
        local world = controller_world.start_world({ list_layout = list_layout.ROWS })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["2"]()
        expect.equal(world.read_overlay(), {
            " 1   Microsoft Word",
            " Draft.docx",
            " 2   Safari",
            ">Inbox",
            " Reading list",
        })
        world.app_hotkeys["2"]()
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 64" })
        expect.equal(world.focused_window_id, reading.id)
    end,

    a_list_of_the_window_server_above_64_kib_reaches_the_numbered_list = function()
        local world = controller_world.start_world({ list_layout = list_layout.ROWS })
        world.is_server_list_above_64_kib = true
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["2"]()
        expect.equal(world.read_overlay(), {
            " 1   Microsoft Word",
            " Draft.docx",
            " 2   Safari",
            ">Inbox",
            " Reading list",
        })
    end,

    the_list_reaches_a_window_in_full_screen = function()
        local world = controller_world.start_world()
        world.displays[1].full_screen_space_ids = { 500 }
        world.windows[41].space_id = 500
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "5", app = "Safari" }
        )
        world.app_hotkeys["5"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 500" })
        expect.equal(world.displays[1].active_space_id, 500)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.notifications, {})
    end,

    a_press_holds_its_message_until_accessibility_reaches_the_window = function()
        local timing = fake_worlds.create_default_timing()
        timing.window_reach_timeout_seconds = 3
        local world, controller =
            controller_world.start_world({ list_layout = list_layout.ROWS, timing = timing })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.reach_delay_seconds = 1.5
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["2"]()
        world.app_hotkeys["2"]()
        world.release_modifiers()
        local was_released_before_the_focus = false
        for _ = 1, 100 do
            world.advance(0.05)
            if world.focused_window_id == reading.id then
                break
            end
            if #world.mission_control_actions > 0 and not controller.is_press_running then
                was_released_before_the_focus = true
            end
        end
        expect.equal(world.mission_control_actions, { "show 64" })
        expect.equal(world.focused_window_id, reading.id)
        expect.equal(was_released_before_the_focus, false)
        world.advance(1)
        expect.equal(controller.is_press_running, false)
        local _, visible_count = controller_world.read_busy_messages(world)
        expect.equal(visible_count, 0)
    end,

    a_window_that_accessibility_does_not_reach_after_a_press_is_reported = function()
        local world = controller_world.start_world({ list_layout = list_layout.ROWS })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.unreachable_window_ids[reading.id] = true
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["2"]()
        world.app_hotkeys["2"]()
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 64" })
        expect.equal(world.notifications, {
            'Safari window "Reading list" did not appear within 1 seconds after its desktop'
                .. " showed (1 problems in the Hammerspoon console)",
        })
        expect.equal(world.focused_window_id, nil)
    end,

    the_console_says_why_a_slow_snapshot_stops_the_snapshots = function()
        local world =
            controller_world.start_world({ preview_method = preview_method.BLURRED_SNAPSHOTS })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.snapshot_seconds = 1
        local lines = controller_world.record_log_lines(world, function()
            world.held_modifiers = { ctrl = true, alt = true }
            world.app_hotkeys["1"]()
            world.advance(2)
        end)
        expect.equal(lines, {
            "a snapshot took 1.0 seconds, so the list shows icons until the next reload",
        })
    end,
}
