local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local retained_timers = require("desktop_manager.macos.retained_timers")

---@param world table
---@return string[] the focus operations on windows, in order
local function list_focus_operations(world)
    local focuses = {}
    for _, operation in ipairs(world.window_operations) do
        if operation:match("^focus ") then
            table.insert(focuses, operation)
        end
    end
    return focuses
end

return {
    the_search_shows_every_window_above_the_applications = function()
        local world = controller_world.start_world()
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.focused_window_id = news.id
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        expect.equal(world.read_search_panel(), {
            line = { "Type to search the titles and the applications", "3 windows" },
            windows = {
                "selection Inbox | Safari",
                "plain Draft.docx | Microsoft Word",
                "plain News | Safari",
            },
            applications = { "plain 1 | Safari", "plain 2 | Microsoft Word" },
        })
    end,

    typing_shows_only_the_matches_at_their_levels_and_return_brings_the_best = function()
        local world = controller_world.start_world()
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.type_keys("n")
        world.advance(0)
        local panel = world.read_search_panel()
        expect.equal(panel.line, { "n▏", "2 of 3 windows match" })
        expect.equal(panel.windows, { "selection News | Safari", "match-weak Inbox | Safari" })
        expect.equal(panel.applications, { "match-strong 1 | Safari", "faded 2 | Microsoft Word" })
        world.press_key("tab")
        world.advance(0)
        expect.equal(world.read_search_panel().windows[2], "selection Inbox | Safari")
        world.press_key("tab", { shift = true })
        world.type_keys(utf8.char(0xF702))
        world.press_key("return")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.read_search_panel(), nil)
        expect.equal(world.focused_window_id, news.id)
    end,

    hovering_over_an_application_shows_its_windows_and_a_click_on_one_reaches_it = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.move_mouse_to("application:com.microsoft.Word")
        world.advance(0)
        local panel = world.read_search_panel()
        expect.equal(panel.line[2], "1 window of Microsoft Word")
        expect.equal(panel.windows, { "selection Draft.docx | Microsoft Word" })
        expect.equal(panel.applications[2], "hovered 1 | Microsoft Word")
        world.move_mouse_out_of_panel()
        world.advance(0)
        expect.equal(#world.read_search_panel().windows, 2)
        world.click("window:41")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.read_search_panel(), nil)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.displays[1].active_space_id, 14)
    end,

    a_click_chooses_an_application_until_typing = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.click("application:com.microsoft.Word")
        world.move_mouse_to("application:com.apple.Safari")
        world.advance(0)
        local panel = world.read_search_panel()
        expect.equal(panel.line[2], "1 window of Microsoft Word, chosen")
        expect.equal(panel.windows, { "selection Draft.docx | Microsoft Word" })
        expect.equal(panel.applications, { "hovered 2 | Safari", "selection 1 | Microsoft Word" })
        world.type_keys("inbox")
        world.advance(0)
        expect.equal(world.read_search_panel().windows, { "selection Inbox | Safari" })
        world.press_escape()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.read_search_panel(), nil)
        expect.equal(world.focused_window_id, nil)
    end,

    the_search_focuses_the_application_before_the_press_so_that_the_desktop_stays = function()
        local world, notes = controller_world.start_bounce_world()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.type_keys("report")
        world.advance(0)
        expect.equal(
            world.read_search_panel().windows,
            { "selection Report.docx | Microsoft Word" }
        )
        world.press_key("return")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.bounces, {})
        expect.equal(world.displays[2].active_space_id, 9)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(list_focus_operations(world), { "focus " .. notes.id, "focus 43" })
        expect.equal(world.focused_window_id, 43)
        expect.equal(world.notifications, {})
    end,

    the_search_focuses_the_application_before_the_press_for_a_window_not_reached = function()
        local world, notes = controller_world.start_bounce_world()
        local letter = world.create_unseen_window("com.microsoft.Word", "Letter.docx", 10)
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.type_keys("letter")
        world.advance(0)
        expect.equal(
            world.read_search_panel().windows,
            { "selection Letter.docx | Microsoft Word" }
        )
        world.press_key("return")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.bounces, {})
        expect.equal(world.displays[2].active_space_id, 10)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(list_focus_operations(world), { "focus " .. notes.id, "focus " .. letter.id })
        expect.equal(world.notifications, {})
    end,

    the_search_reaches_a_window_on_a_desktop_not_visited = function()
        local world = controller_world.start_world()
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.type_keys("read")
        world.advance(0)
        expect.equal(world.read_search_panel().windows, { "selection Reading list | Safari" })
        world.press_key("return")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 64" })
        expect.equal(world.focused_window_id, reading.id)
        local shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Showing desktop 3 of built-in… please wait")
    end,

    a_press_of_the_search_during_a_switch_is_refused = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.click("window:41")
        world.advance(0)
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        expect.equal(world.notifications, {})
        local shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Arranging Profile 1… please wait")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {})
    end,

    closing_the_search_writes_how_long_its_opening_took = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        local lines = controller_world.record_log_lines(world, function()
            world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
            world.key_wait_seconds = 0.03
            world.decode_seconds = 0.01
            world.type_keys("d")
            world.advance(1)
            world.press_escape()
            world.advance(0)
        end)
        expect.equal(lines, {
            "search of 2 windows: shown after 0.000 seconds, first preview after 0.260 seconds,"
                .. " 2 of 2 previews by 0.310 seconds, blocking Hammerspoon for 0.020 seconds in"
                .. " total and 0.010 seconds at most, list of the window server after 0.260"
                .. " seconds, blocking Hammerspoon for 0.000 seconds, 2 keys, waiting 0.030"
                .. " seconds at most",
        })
    end,

    a_key_that_a_program_made_counts_without_a_wait = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        local lines = controller_world.record_log_lines(world, function()
            world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
            world.key_wait_seconds = nil
            world.type_keys("d")
            world.advance(1)
            world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
            world.advance(0)
        end)
        expect.equal(lines, {
            "search of 2 windows: shown after 0.000 seconds, first preview after 0.250 seconds,"
                .. " 2 of 2 previews by 0.300 seconds, blocking Hammerspoon for 0.000 seconds in"
                .. " total and 0.000 seconds at most, list of the window server after 0.250"
                .. " seconds, blocking Hammerspoon for 0.000 seconds, 1 key",
        })
    end,

    the_list_and_the_search_read_each_icon_once_until_its_application_quits = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.bundle_ids_without_icon["com.apple.Notes"] = true
        world.create_window("com.apple.Notes", "Shopping")
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        expect.equal(world.read_overlay_images(), {
            "icon com.apple.Safari",
            "icon com.microsoft.Word",
            "icon com.apple.Safari",
            "icon com.microsoft.Word",
        })
        world.press_escape()
        world.advance(controller_world.SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.press_escape()
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(
            world.icon_reads,
            { ["com.apple.Safari"] = 1, ["com.microsoft.Word"] = 1, ["com.apple.Notes"] = 1 }
        )
        world.terminate_application("com.apple.Safari")
        world.applications["com.apple.Safari"].is_running = true
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        expect.equal(
            world.icon_reads,
            { ["com.apple.Safari"] = 2, ["com.microsoft.Word"] = 1, ["com.apple.Notes"] = 1 }
        )
    end,

    the_search_reads_the_window_filter_once_before_the_panel_shows = function()
        local world = controller_world.start_world()
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.SETTLE_SECONDS)
        local reads_before = world.filter_reads
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        expect.equal(world.filter_reads - reads_before, 1)
        expect.equal(world.read_search_panel().windows, {
            "selection Inbox | Safari",
            "plain Draft.docx | Microsoft Word",
            "plain Reading list | Safari",
        })
    end,

    the_search_starts_the_helper_after_drawing_and_shows_each_preview_while_keys_come = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        local snapshots_before = world.snapshot_count
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.advance(0.04)
        expect.equal(#world.helpers, 0)
        world.press_key("tab")
        world.advance(0.02)
        expect.equal(#world.helpers, 1)
        expect.equal({ table.unpack(world.helpers[1].arguments, 6) }, { "41", "42" })
        world.advance(0.15)
        expect.equal(world.snapshot_count, snapshots_before)
        world.advance(0.05)
        expect.equal(world.snapshot_count, snapshots_before + 1)
        world.press_key("tab")
        world.advance(0.05)
        expect.equal(world.snapshot_count, snapshots_before + 2)
        expect.equal(world.read_overlay_images(), {
            "blurred 41",
            "blurred 42",
            "icon com.apple.Safari",
            "icon com.microsoft.Word",
        })
    end,

    the_previews_of_one_chunk_of_the_helper_give_one_redraw = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        world.gives_helper_lines_at_once = true
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.advance(0.26)
        local redraws_before = world.overlay.replace_count
        expect.equal(world.read_overlay_images()[1], "icon com.apple.Safari")
        world.advance(0.1)
        expect.equal(world.overlay.replace_count, redraws_before + 1)
        expect.equal(world.read_overlay_images(), {
            "blurred 41",
            "blurred 42",
            "icon com.apple.Safari",
            "icon com.microsoft.Word",
        })
    end,

    a_last_line_that_comes_with_the_exit_of_the_helper_or_after_it_shows_its_preview = function()
        for _, route in ipairs({ "exit_output", "stream_after_exit" }) do
            local world = controller_world.start_world()
            world.advance(controller_world.SETTLE_SECONDS)
            world.last_helper_line_route = route
            local lines = controller_world.record_log_lines(world, function()
                world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
                world.advance(3)
            end)
            expect.equal(lines, {})
            expect.equal(world.read_overlay_images()[2], "blurred 42")
        end
    end,

    a_helper_that_keeps_giving_lines_runs_past_the_limit_of_its_silence = function()
        local world = controller_world.start_world()
        world.create_window("com.apple.Safari", "News")
        world.create_window("com.apple.Safari", "Weather")
        world.advance(controller_world.SETTLE_SECONDS)
        world.snapshot_seconds = 0.45
        local lines = controller_world.record_log_lines(world, function()
            world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
            world.advance(3)
        end)
        expect.equal(lines, {})
        expect.equal(world.snapshot_count, 4)
        expect.equal(world.read_overlay_images()[4]:match("^blurred"), "blurred")
    end,

    a_line_that_names_no_window_and_no_image_ends_the_helper = function()
        for _, gives_helper_lines_at_once in ipairs({ false, true }) do
            local world = controller_world.start_world()
            world.advance(controller_world.SETTLE_SECONDS)
            world.garbled_window_ids[41] = true
            world.gives_helper_lines_at_once = gives_helper_lines_at_once
            local lines = controller_world.record_log_lines(world, function()
                world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
                world.advance(1)
            end)
            expect.equal(lines, {
                "the helper of the previews gave a line that names no window and no image, so the"
                    .. " windows without a preview show their icons",
            })
            expect.equal(world.helpers[1].is_terminated, true)
            expect.equal(world.read_overlay_images()[2], "icon com.microsoft.Word")
        end
    end,

    closing_the_search_terminates_its_helper_and_the_next_opening_takes_previews = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        local snapshots_before = world.snapshot_count
        local lines = controller_world.record_log_lines(world, function()
            world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
            world.advance(0.26)
            world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
            world.advance(2)
        end)
        expect.equal(world.helpers[1].is_terminated, true)
        expect.equal(world.snapshot_count, snapshots_before + 1)
        expect.equal(#lines, 1)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.advance(1)
        expect.equal(world.snapshot_count, snapshots_before + 3)
        expect.equal(world.read_overlay_images()[2], "blurred 42")
    end,

    a_silent_helper_ends_and_leaves_the_icons_of_that_opening_alone = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        world.helper_start_seconds = 5
        local lines = controller_world.record_log_lines(world, function()
            world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
            world.advance(1.54)
        end)
        expect.equal(lines, {})
        expect.equal(world.helpers[1].is_running, true)
        lines = controller_world.record_log_lines(world, function()
            world.advance(0.02)
        end)
        expect.equal(lines, {
            "the helper of the previews gave nothing for 1.5 seconds, so the windows without a"
                .. " preview show their icons",
        })
        expect.equal(world.helpers[1].is_terminated, true)
        expect.equal(world.read_overlay_images()[1], "icon com.apple.Safari")
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.helper_start_seconds = 0.15
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.advance(1)
        expect.equal(world.read_overlay_images()[1], "blurred 41")
    end,

    a_helper_that_ends_with_another_status_says_so_and_the_next_opening_takes_previews = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        world.helper_exit_code = 1
        local unseen = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        local lines = controller_world.record_log_lines(world, function()
            world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
            world.advance(1)
        end)
        expect.equal(lines, {
            "the helper of the previews ended with status 1, so the windows without a preview show"
                .. " their icons",
        })
        expect.equal(#world.helpers, 1)
        expect.equal(world.read_overlay_images()[3], "icon com.apple.Safari")
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.helper_exit_code = 0
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.advance(1)
        expect.equal(world.read_overlay_images()[3], "blurred " .. unseen.id)
    end,

    a_window_found_after_the_panel_opened_joins_it = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        expect.equal(#world.read_search_panel().windows, 2)
        world.advance(1)
        expect.equal(world.read_search_panel().windows[3], "plain Reading list | Safari")
    end,

    a_window_found_after_the_panel_opened_waits_in_the_queue_of_the_previews = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        local unseen = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        local snapshots_before = world.snapshot_count
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.advance(0.26)
        expect.equal(world.read_search_panel().windows[3], "plain Reading list | Safari")
        expect.equal(#world.helpers, 1)
        world.advance(0.05)
        expect.equal(#world.helpers, 2)
        expect.equal({ table.unpack(world.helpers[2].arguments, 6) }, { tostring(unseen.id) })
        world.advance(1)
        expect.equal(world.snapshot_count, snapshots_before + 3)
        expect.equal(world.read_overlay_images()[3], "blurred " .. unseen.id)
    end,

    closing_the_search_before_its_drawing_starts_no_helper = function()
        local world = controller_world.start_world()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.advance(0.04)
        local timers_before = retained_timers.count_running()
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        expect.equal(retained_timers.count_running() < timers_before, true)
        world.advance(1)
        expect.equal(#world.helpers, 0)
    end,

    a_window_that_its_application_keeps_ordered_out_shows_in_no_list = function()
        local world = controller_world.start_world()
        local closed = world.create_unseen_window("com.apple.Notes", "New Note", 64)
        world.windows[closed.id].is_ordered_out = true
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.SETTLE_SECONDS)
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.advance(1)
        expect.equal(#world.read_search_panel().windows, 3)
        expect.equal(world.read_search_panel().windows[3], "plain Reading list | Safari")
    end,

    the_arrows_move_the_selection_in_the_grid_of_the_previews = function()
        local world = controller_world.start_world()
        world.create_window("com.apple.Safari", "News")
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        local function press_and_read(key)
            world.press_key(key)
            world.advance(0)
            local selected = {}
            for _, window in ipairs(world.read_search_panel().windows) do
                if window:match("^selection") then
                    table.insert(selected, window)
                end
            end
            return selected
        end
        expect.equal(press_and_read("right"), { "selection Draft.docx | Microsoft Word" })
        expect.equal(press_and_read("right"), { "selection News | Safari" })
        expect.equal(press_and_read("right"), { "selection News | Safari" })
        expect.equal(press_and_read("down"), { "selection News | Safari" })
        expect.equal(press_and_read("left"), { "selection Draft.docx | Microsoft Word" })
        expect.equal(press_and_read("tab"), { "selection News | Safari" })
        expect.equal(press_and_read("tab"), { "selection Inbox | Safari" })
    end,

    down_reaches_the_next_row_of_the_grid = function()
        local world = controller_world.start_world({ list_font_size = 0.01 })
        for _, title in ipairs({ "News", "Weather", "Maps" }) do
            world.create_window("com.apple.Safari", title)
        end
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.press_key("down")
        world.advance(0)
        local windows = world.read_search_panel().windows
        expect.equal(#windows, 5)
        expect.equal(windows[4], "selection Weather | Safari")
        world.press_key("up")
        world.advance(0)
        expect.equal(world.read_search_panel().windows[1], "selection Inbox | Safari")
    end,

    the_search_shortcut_again_closes_the_search = function()
        local world = controller_world.start_world()
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        expect.present(world.read_search_panel(), "the search panel")
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        expect.equal(world.read_search_panel(), nil)
        world.type_keys("x")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.read_search_panel(), nil)
    end,

    return_without_a_match_keeps_the_search = function()
        local world = controller_world.start_world()
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.type_keys("zz")
        world.press_key("return")
        world.advance(controller_world.SETTLE_SECONDS)
        local panel = world.read_search_panel()
        expect.equal(panel.line[2], "no window matches")
        expect.equal(panel.note, "No window matches")
    end,

    a_url_opens_the_search = function()
        local world = controller_world.start_world()
        world.url_handlers["desktop-manager"]("desktop-manager", { action = "search-windows" })
        expect.equal(world.read_search_panel().line[2], "2 windows")
    end,
}
