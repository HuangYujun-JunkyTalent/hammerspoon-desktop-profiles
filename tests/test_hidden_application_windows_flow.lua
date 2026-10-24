local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local fake_worlds = require("tests.fake_worlds")
local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")
local list_layout = require("desktop_manager.core.list_layout")

---A world under the value of hidden_application_windows, after profile 1 recorded it, with Safari
---and Microsoft Word hidden and the windows that accessibility does not reach listed again.
---Window 41 of Safari, on desktop 14 out of view, keeps its subrole while hidden, so the window
---filter keeps it.
---Window 42 of Word, on desktop 3 in view, and the window "Notes.docx" of Word, on desktop 64 out
---of view, report `AXDialog` while Word is hidden, so the window filter drops them, and the list of
---the window server holds "Notes.docx" alone.
---@param setting string a value of hidden_application_windows
---@return table world
---@return ProfileController controller
---@return table notes the window "Notes.docx" of the fake world
local function start_world_with_hidden_applications(setting)
    local world, controller = controller_world.start_world({
        hidden_application_windows = setting,
        list_layout = list_layout.ROWS,
    })
    local notes = world.add_window_of("com.microsoft.Word", "Notes.docx", 64)
    world.hotkeys["1"]()
    world.advance(controller_world.SETTLE_SECONDS)
    world.applications["com.microsoft.Word"].is_dropped_by_filter_while_hidden = true
    world.hide_application("com.microsoft.Word")
    world.hide_application("com.apple.Safari")
    world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
    return world, controller, notes
end

---Holds Control and Option, presses the number and reads the list.
---@param world table
---@param number string
---@return string[] the texts of the list
local function read_list_after_press(world, number)
    world.held_modifiers = { ctrl = true, alt = true }
    world.app_hotkeys[number]()
    return world.read_overlay()
end

---Opens the search, waits for the new list of the window server, and reads the previews.
---@param world table
---@return string[] the previews of the search
local function read_search_windows(world)
    world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
    world.advance(1)
    return world.read_search_panel().windows
end

return {
    the_list_leaves_out_the_windows_of_hidden_applications_by_default = function()
        expect.equal(
            fake_worlds.create_default_settings().hidden_application_windows,
            hidden_application_windows.LEAVE_OUT
        )
        local world = start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        local reads_before = {
            safari = world.application_window_reads["com.apple.Safari"] or 0,
            word = world.application_window_reads["com.microsoft.Word"] or 0,
        }
        local hidden_reads_before = {
            safari = world.hidden_reads["com.apple.Safari"] or 0,
            word = world.hidden_reads["com.microsoft.Word"] or 0,
        }
        expect.equal(read_list_after_press(world, "1"), {
            ">1   Microsoft Word",
            " hidden, a press unhides it",
            " 2   Safari",
            " hidden, a press unhides it",
        })
        expect.equal(world.application_window_reads["com.apple.Safari"] or 0, reads_before.safari)
        expect.equal(world.application_window_reads["com.microsoft.Word"] or 0, reads_before.word)
        expect.equal(world.hidden_reads["com.apple.Safari"] or 0, hidden_reads_before.safari)
        expect.equal(world.hidden_reads["com.microsoft.Word"] or 0, hidden_reads_before.word)
    end,

    the_search_leaves_out_the_windows_of_hidden_applications_by_default = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        local hidden_reads_before = world.hidden_reads["com.microsoft.Word"] or 0
        expect.equal(read_search_windows(world), {})
        expect.equal(world.hidden_reads["com.microsoft.Word"] or 0, hidden_reads_before)
    end,

    the_list_shows_the_windows_of_hidden_applications_where_found = function()
        local world =
            start_world_with_hidden_applications(hidden_application_windows.LIST_WHERE_FOUND)
        world.terminate_application("com.apple.Notes")
        local hidden_reads_before = world.hidden_reads["com.apple.Safari"] or 0
        expect.equal(read_list_after_press(world, "1"), {
            ">1   Microsoft Word",
            " Notes.docx",
            " 2   Safari",
            " Inbox",
        })
        expect.equal(world.hidden_reads["com.apple.Safari"] or 0, hidden_reads_before)
    end,

    the_search_shows_the_windows_of_hidden_applications_where_found = function()
        local world, _, notes =
            start_world_with_hidden_applications(hidden_application_windows.LIST_WHERE_FOUND)
        expect.equal(read_search_windows(world), {
            "selection Inbox | Safari",
            "plain Notes.docx | Microsoft Word",
        })
        world.click("window:" .. notes.id)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.focused_window_id, notes.id)
        expect.equal(world.displays[1].active_space_id, 64)
    end,

    the_list_shows_every_window_of_hidden_applications_and_a_choice_unhides = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LIST_ALL)
        expect.equal(read_list_after_press(world, "1"), {
            " 1   Microsoft Word",
            ">Draft.docx",
            " Notes.docx",
            " 2   Safari",
            " Inbox",
        })
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.focused_window_id, 42)
    end,

    the_search_shows_every_window_of_hidden_applications_and_a_choice_unhides = function()
        local world, _, notes =
            start_world_with_hidden_applications(hidden_application_windows.LIST_ALL)
        expect.equal(read_search_windows(world), {
            "selection Inbox | Safari",
            "plain Draft.docx | Microsoft Word",
            "plain Notes.docx | Microsoft Word",
        })
        world.click("window:" .. notes.id)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.focused_window_id, notes.id)
        expect.equal(world.displays[1].active_space_id, 64)
    end,

    every_window_of_hidden_applications_leaves_out_their_other_elements = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LIST_ALL)
        local sheet = world.add_window_of("com.microsoft.Word", "Save changes?", 3)
        world.windows[sheet.id].role = "AXSheet"
        expect.equal(read_list_after_press(world, "1")[4], " 2   Safari")
        world.press_escape()
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(read_search_windows(world), {
            "selection Inbox | Safari",
            "plain Draft.docx | Microsoft Word",
            "plain Notes.docx | Microsoft Word",
        })
    end,

    the_search_reads_every_window_only_of_hidden_applications_with_a_dock_icon = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LIST_ALL)
        world.unhide_application("com.apple.Safari")
        local notes_application = world.applications["com.apple.Notes"]
        notes_application.is_running = true
        notes_application.kind = 0
        world.add_window_of("com.apple.Notes", "Shopping", 3)
        notes_application.is_dropped_by_filter_while_hidden = true
        world.hide_application("com.apple.Notes")
        local reads_before = {}
        local bundle_ids = { "com.apple.Safari", "com.microsoft.Word", "com.apple.Notes" }
        for _, bundle_id in ipairs(bundle_ids) do
            reads_before[bundle_id] = world.application_window_reads[bundle_id] or 0
        end
        expect.equal(read_search_windows(world), {
            "selection Inbox | Safari",
            "plain Draft.docx | Microsoft Word",
            "plain Notes.docx | Microsoft Word",
        })
        local reads = {}
        for bundle_id, count in pairs(reads_before) do
            reads[bundle_id] = (world.application_window_reads[bundle_id] or 0) - count
        end
        expect.equal(
            reads,
            { ["com.apple.Safari"] = 0, ["com.microsoft.Word"] = 1, ["com.apple.Notes"] = 0 }
        )
    end,

    the_list_asks_whether_an_application_is_hidden_once_and_then_follows_macos = function()
        local world = controller_world.start_world({
            hidden_application_windows = hidden_application_windows.LEAVE_OUT,
            list_layout = list_layout.ROWS,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        ---Opens the list, reads it and closes it.
        ---@return string[] texts the texts of the list
        ---@return integer hidden_reads the calls of isHidden while the list opened
        local function read_list_and_close()
            local reads_before = (world.hidden_reads["com.apple.Safari"] or 0)
                + (world.hidden_reads["com.microsoft.Word"] or 0)
            local texts = read_list_after_press(world, "2")
            local hidden_reads = (world.hidden_reads["com.apple.Safari"] or 0)
                + (world.hidden_reads["com.microsoft.Word"] or 0)
                - reads_before
            world.press_escape()
            world.release_modifiers()
            world.advance(controller_world.SETTLE_SECONDS)
            return texts, hidden_reads
        end
        local shown = { " 1   Microsoft Word", " Draft.docx", " 2   Safari", ">Inbox" }
        local texts, hidden_reads = read_list_and_close()
        expect.equal(texts, shown)
        expect.equal(hidden_reads, 2)
        texts, hidden_reads = read_list_and_close()
        expect.equal(texts, shown)
        expect.equal(hidden_reads, 0)
        world.hide_application("com.apple.Safari")
        texts, hidden_reads = read_list_and_close()
        expect.equal(texts[4], " hidden, a press unhides it")
        expect.equal(hidden_reads, 0)
        world.unhide_application("com.apple.Safari")
        texts, hidden_reads = read_list_and_close()
        expect.equal(texts, shown)
        expect.equal(hidden_reads, 0)
        world.hide_application("com.apple.Safari")
        world.terminate_application("com.apple.Notes")
        world.applications["com.apple.Safari"].is_hidden = false
        texts, hidden_reads = read_list_and_close()
        expect.equal(texts, shown)
        expect.equal(hidden_reads, 2)
    end,

    the_list_searches_no_window_for_a_numbered_application_that_is_closed = function()
        local world = controller_world.start_world({ list_layout = list_layout.ROWS })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.applications["com.apple.Safari"].is_running = false
        local calls_before = world.all_windows_calls
        read_list_after_press(world, "1")
        expect.equal(world.all_windows_calls, calls_before)
    end,

    a_press_of_a_hidden_application_under_leave_out_shows_the_desktop_of_its_window = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        read_list_after_press(world, "2")
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.menu_selections, {})
        local shown, visible_count = controller_world.read_busy_messages(world)
        expect.equal({ shown[#shown - 1], shown[#shown] }, {
            "Arranging Profile 1… please wait",
            "Showing desktop 2 of built-in… please wait",
        })
        expect.equal(visible_count, 0)
    end,

    a_press_of_a_hidden_application_reaches_its_window_on_a_desktop_not_shown_yet = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        world.windows[41].is_unseen = true
        read_list_after_press(world, "2")
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.menu_selections, {})
    end,

    a_press_of_hidden_word_shows_the_desktop_of_its_only_window_before_the_unhide = function()
        local world, controller, notes =
            start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        world.close_window(42)
        world.windows[notes.id].is_unseen = true
        world.applications["com.microsoft.Word"].standard_delay_after_unhide_seconds = 0.5
        local window_count = #world.window_order
        read_list_after_press(world, "1")
        world.release_modifiers()
        world.advance(0.45)
        expect.equal(world.displays[1].active_space_id, 64)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, true)
        world.advance(0.35)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.focused_window_id == notes.id, false)
        local shown, visible_while_waiting = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Showing desktop 3 of built-in… please wait")
        expect.equal(visible_while_waiting, 1)
        expect.equal(controller.is_press_running, true)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, notes.id)
        expect.equal(world.menu_selections, {})
        expect.equal(#world.window_order, window_count)
        local _, visible_count = controller_world.read_busy_messages(world)
        expect.equal(visible_count, 0)
        expect.equal(controller.is_press_running, false)
    end,

    a_window_on_another_desktop_without_a_standard_subrole_in_time_is_reported = function()
        local world, _, notes =
            start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        world.close_window(42)
        world.windows[notes.id].is_unseen = true
        world.applications["com.microsoft.Word"].standard_delay_after_unhide_seconds = 5
        read_list_after_press(world, "1")
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(
            world.alerts[#world.alerts],
            "Microsoft Word showed no standard window in the 1-second wait"
                .. " after its unhide (1 problems in the Hammerspoon console)"
        )
        expect.equal(world.focused_window_id == notes.id, false)
        expect.equal(world.menu_selections, {})
    end,

    a_hidden_application_without_reached_windows_shows_a_recorded_desktop = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        world.windows[41].is_unseen = true
        world.unreachable_window_ids[41] = true
        read_list_after_press(world, "2")
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.menu_selections, { "com.apple.Safari New Window" })
        expect.equal(
            world.focused_window_id,
            controller_world.find_window_titled(world, "Start Page").id
        )
    end,

    a_press_of_hidden_word_under_leave_out_waits_for_a_standard_window_and_opens_none = function()
        local world, controller =
            start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        world.applications["com.microsoft.Word"].standard_delay_after_unhide_seconds = 0.5
        local window_count = #world.window_order
        read_list_after_press(world, "1")
        world.release_modifiers()
        world.advance(0.3)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.focused_window_id == 42, false)
        local shown, visible_while_waiting = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Unhiding Microsoft Word… please wait")
        expect.equal(visible_while_waiting, 1)
        expect.equal(controller.is_press_running, true)
        world.advance(0.4)
        expect.equal(world.focused_window_id, 42)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 42)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.menu_selections, {})
        expect.equal(#world.window_order, window_count)
        local _, visible_count = controller_world.read_busy_messages(world)
        expect.equal(visible_count, 0)
        expect.equal(controller.is_press_running, false)
        expect.equal(world.notifications, {})
    end,

    a_press_of_a_hidden_application_under_leave_out_prefers_its_main_window = function()
        local world, _, notes =
            start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        world.applications["com.microsoft.Word"].main_window_id = notes.id
        world.applications["com.microsoft.Word"].standard_delay_after_unhide_seconds = 0.5
        read_list_after_press(world, "1")
        world.release_modifiers()
        world.advance(0.3)
        local shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Showing desktop 3 of built-in… please wait")
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, notes.id)
        expect.equal(world.displays[1].active_space_id, 64)
        expect.equal(world.menu_selections, {})
    end,

    a_press_of_hidden_word_in_view_brings_its_minimized_main_window_after_the_wait = function()
        local world, controller =
            start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        local other = world.add_window_of("com.microsoft.Word", "Other.docx", 3)
        world.windows[other.id].is_minimized = true
        world.applications["com.microsoft.Word"].main_window_id = other.id
        world.applications["com.microsoft.Word"].standard_delay_after_unhide_seconds = 0.5
        read_list_after_press(world, "1")
        world.release_modifiers()
        world.advance(0.3)
        expect.equal(world.focused_window_id == other.id, false)
        local shown = controller_world.read_busy_messages(world)
        expect.equal(shown[#shown], "Unhiding Microsoft Word… please wait")
        expect.equal(controller.is_press_running, true)
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.focused_window_id, other.id)
        expect.equal(world.windows[other.id].is_minimized, false)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.menu_selections, {})
    end,

    a_hidden_application_without_a_standard_window_in_time_is_reported = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        world.applications["com.microsoft.Word"].standard_delay_after_unhide_seconds = 5
        local window_count = #world.window_order
        read_list_after_press(world, "1")
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(
            world.alerts[#world.alerts],
            "Microsoft Word showed no standard window in the 1-second wait"
                .. " after its unhide (1 problems in the Hammerspoon console)"
        )
        expect.equal(world.menu_selections, {})
        expect.equal(#world.window_order, window_count)
    end,

    a_hidden_application_without_any_window_gets_a_new_window = function()
        local world = controller_world.start_world({
            hidden_application_windows = hidden_application_windows.LEAVE_OUT,
            list_layout = list_layout.ROWS,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.close_window(41)
        world.hide_application("com.apple.Safari")
        expect.equal(read_list_after_press(world, "2"), {
            " 1   Microsoft Word",
            " Draft.docx",
            ">2   Safari",
            " hidden, a press unhides it",
        })
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(world.menu_selections, { "com.apple.Safari New Window" })
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(
            world.focused_window_id,
            controller_world.find_window_titled(world, "Start Page").id
        )
    end,

    the_columns_mark_a_hidden_application_under_leave_out = function()
        local world = controller_world.start_world({
            hidden_application_windows = hidden_application_windows.LEAVE_OUT,
        })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.hide_application("com.apple.Safari")
        expect.equal(read_list_after_press(world, "1"), {
            " 1  Microsoft Word",
            ">Draft.docx",
            " 2  Safari",
            " hidden, a press unhides it",
        })
    end,

    a_hidden_application_without_windows_keeps_its_note_under_the_other_values = function()
        for _, setting in ipairs({
            hidden_application_windows.LIST_WHERE_FOUND,
            hidden_application_windows.LIST_ALL,
        }) do
            local world = controller_world.start_world({
                hidden_application_windows = setting,
                list_layout = list_layout.ROWS,
            })
            world.hotkeys["1"]()
            world.advance(controller_world.SETTLE_SECONDS)
            world.close_window(41)
            world.hide_application("com.apple.Safari")
            expect.equal(read_list_after_press(world, "2")[4], " no window, a new one opens")
        end
    end,

    every_window_of_hidden_applications_includes_those_accessibility_does_not_reach = function()
        local world, _, notes =
            start_world_with_hidden_applications(hidden_application_windows.LIST_ALL)
        world.windows[notes.id].is_unseen = true
        expect.equal(read_list_after_press(world, "1"), {
            " 1   Microsoft Word",
            ">Draft.docx",
            " Notes.docx",
            " 2   Safari",
            " Inbox",
        })
        world.press_escape()
        world.release_modifiers()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(read_search_windows(world), {
            "selection Inbox | Safari",
            "plain Draft.docx | Microsoft Word",
            "plain Notes.docx | Microsoft Word",
        })
    end,

    the_list_joins_a_standard_window_that_the_filter_misses_under_every_value = function()
        for _, setting in ipairs({
            hidden_application_windows.LEAVE_OUT,
            hidden_application_windows.LIST_WHERE_FOUND,
            hidden_application_windows.LIST_ALL,
        }) do
            local world = controller_world.start_world({
                hidden_application_windows = setting,
                list_layout = list_layout.ROWS,
            })
            local missed = world.add_window_of("com.apple.Safari", "Reading List", 3)
            world.windows[missed.id].is_missed_by_filter = true
            world.hotkeys["1"]()
            world.advance(controller_world.SETTLE_SECONDS)
            local panel = world.add_window_of("com.apple.Safari", "Downloads", 3)
            world.windows[panel.id].is_missed_by_filter = true
            world.windows[panel.id].is_standard = false
            expect.equal(read_list_after_press(world, "2"), {
                " 1   Microsoft Word",
                " Draft.docx",
                " 2   Safari",
                ">Inbox",
                " Reading List",
            })
        end
    end,
}
