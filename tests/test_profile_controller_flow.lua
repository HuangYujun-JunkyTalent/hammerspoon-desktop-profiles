local concealment_method = require("desktop_manager.core.concealment_method")
local default_settings = require("desktop_manager.default_settings")
local list_layout = require("desktop_manager.core.list_layout")
local list_sizing = require("desktop_manager.core.list_sizing")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local preview_method = require("desktop_manager.core.preview_method")
local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local profile_controller = require("desktop_manager.macos.profile_controller")
local profile_state = require("desktop_manager.core.profile_state")
local retained_timers = require("desktop_manager.macos.retained_timers")
local shortcut_center = require("keyboard_shortcuts.macos.shortcut_center")
local switch_desktops = require("desktop_manager.macos.switch_desktops")
local tiling_controller = require("window_tiling.macos.tiling_controller")
local tiling_settings = require("window_tiling.default_settings")
local title_overflow = require("desktop_manager.core.title_overflow")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }
local BUILTIN_SCREEN = {
    id = 1,
    uuid = "BUILTIN-UUID",
    name = "Built-in Retina Display",
    frame = BUILTIN_FRAME,
}
local DELL_SCREEN = {
    id = 2,
    uuid = "DELL-UUID",
    name = "DELL S2725DS",
    frame = { x = 1440, y = 0, w = 2560, h = 1415 },
}
local SETTLE_SECONDS = 30
local SEARCH_SHORTCUT = "ctrl+alt+cmd space"
local MONITOR_CONFIGURATION_KEY = "built-in"

---Saved frames are fractions of the screen rounded to four decimals, so a restored frame is near
---the original frame and not equal to it.
---@param actual Rect
---@param expected Rect
local function expect_frame_near(actual, expected)
    for _, field in ipairs({ "x", "y", "w", "h" }) do
        if math.abs(actual[field] - expected[field]) > 1 then
            error(
                string.format("expected %s near %g, got %g", field, expected[field], actual[field]),
                2
            )
        end
    end
end

---@param world table
---@param title string
---@return table|nil the window of the fake world with the title
local function find_window_titled(world, title)
    for _, window in pairs(world.windows) do
        if window.title == title then
            return window
        end
    end
    return nil
end

---@param world table
---@param title string
---@return table the item of the menu bar item with the title
local function find_menu_item(world, title)
    for _, item in ipairs(world.menu_builder()) do
        if item.title == title then
            return item
        end
    end
    error("the menu has no item " .. title)
end

---@param controller ProfileController
---@param id string
---@return table the row of the action in the window of the shortcuts
local function find_shortcut_row(controller, id)
    for _, group in ipairs(controller.shortcut_window.model.groups) do
        for _, row in ipairs(group.rows) do
            if row.id == id then
                return row
            end
        end
    end
    error("the window of the shortcuts has no row " .. id)
end

---@param world table
local function open_app_pool_window(world)
    find_menu_item(world, "Managed applications…").fn()
end

---The busy message is a canvas of a background and one text, one canvas per screen.
---@param world table
---@return string[] shown the texts of the busy messages that showed, in order
---@return integer visible_count the canvases of busy messages that still show
local function read_busy_messages(world)
    local shown, visible_count = {}, 0
    for _, canvas in ipairs(world.canvases) do
        local elements = canvas.elements
        if #elements == 2 and elements[2].type == "text" then
            table.insert(shown, elements[2].text)
            visible_count = visible_count + (canvas.is_visible and 1 or 0)
        end
    end
    return shown, visible_count
end

---@param controller ProfileController
---@param number integer
---@param window_id integer
---@return string|nil "in sight" or "out of sight" when the profile recorded the window
local function recorded_sight(controller, number, window_id)
    local arrangement =
        profile_state.find_arrangement(controller.state, number, MONITOR_CONFIGURATION_KEY)
    for _, record in ipairs(arrangement and arrangement.windows or {}) do
        if record.window_id == window_id then
            return record.is_out_of_sight and "out of sight" or "in sight"
        end
    end
    return nil
end

---@param setting_changes table|nil settings that replace the defaults, such as concealment_method
---@return table world
---@return ProfileController controller
local function start_world(setting_changes)
    local world = fake_hammerspoon.install({
        screens = {
            {
                id = 1,
                uuid = "BUILTIN-UUID",
                name = "Built-in Retina Display",
                frame = BUILTIN_FRAME,
            },
        },
        displays = { { uuid = "BUILTIN-UUID", space_ids = { 3, 14, 64 }, active_space_id = 3 } },
        applications = {
            {
                bundle_id = "com.apple.Safari",
                name = "Safari",
                is_running = true,
                new_window_title = "Start Page",
            },
            {
                bundle_id = "com.microsoft.Word",
                name = "Microsoft Word",
                is_running = true,
                new_window_title = "Document1",
            },
            {
                bundle_id = "com.apple.Notes",
                name = "Notes",
                is_running = false,
                launch_titles = { "Shopping" },
            },
        },
        windows = {
            {
                id = 41,
                bundle_id = "com.apple.Safari",
                title = "Inbox",
                space_id = 14,
                frame = { x = 0, y = 25, w = 720, h = 875 },
            },
            {
                id = 42,
                bundle_id = "com.microsoft.Word",
                title = "Draft.docx",
                space_id = 3,
                frame = { x = 720, y = 25, w = 720, h = 875 },
            },
        },
    })
    local settings = default_settings.create("/fake/state.json")
    for name, value in pairs(setting_changes or {}) do
        settings[name] = value
    end
    local controller = profile_controller.start(settings)
    return world, controller
end

---A world with the built-in display and a Dell monitor beside it, with a window on the built-in
---display and two windows on the second and third desktops of the monitor.
---@param builtin_space_ids integer[]
---@param dell_space_ids integer[]
---@return table world
---@return ProfileController controller
local function start_two_screen_world(builtin_space_ids, dell_space_ids)
    local world = fake_hammerspoon.install({
        screens = { BUILTIN_SCREEN, DELL_SCREEN },
        displays = {
            {
                uuid = BUILTIN_SCREEN.uuid,
                space_ids = builtin_space_ids,
                active_space_id = builtin_space_ids[1],
            },
            {
                uuid = DELL_SCREEN.uuid,
                space_ids = dell_space_ids,
                active_space_id = dell_space_ids[1],
            },
        },
        applications = {
            { bundle_id = "com.apple.Safari", name = "Safari", is_running = true },
            { bundle_id = "com.microsoft.Word", name = "Microsoft Word", is_running = true },
        },
        windows = {
            {
                id = 41,
                bundle_id = "com.apple.Safari",
                title = "Inbox",
                space_id = dell_space_ids[2],
                frame = { x = 1440, y = 25, w = 1280, h = 1390 },
            },
            {
                id = 42,
                bundle_id = "com.microsoft.Word",
                title = "Draft.docx",
                space_id = builtin_space_ids[1],
                frame = { x = 0, y = 25, w = 1440, h = 875 },
            },
            {
                id = 43,
                bundle_id = "com.microsoft.Word",
                title = "Report.docx",
                space_id = dell_space_ids[3],
                frame = { x = 2720, y = 25, w = 1280, h = 1390 },
            },
        },
    })
    local controller = profile_controller.start(default_settings.create("/fake/state.json"))
    return world, controller
end

return {
    the_empty_desktops_that_macos_leaves_after_a_monitor_returns_are_removed = function()
        local world, controller = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        expect.equal(controller.state.desktop_counts.kept, { ["built-in"] = 3, ["external 1"] = 4 })
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 8, 9 })
        expect.equal(world.mission_control_actions, { "remove 10" })
        expect.equal(world.is_mission_control_open, false)
        world.advance(61)
        expect.equal(controller.state.desktop_counts.kept, { ["built-in"] = 3, ["external 1"] = 4 })
        world.connect_screen(DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.displays[2].space_ids, { 20, 2000, 2001, 2002 })
        expect.equal(world.windows[41].space_id, 2000)
        expect.equal(world.windows[43].space_id, 2001)
        expect.equal(world.windows[42].space_id, 3)
        expect.equal(world.mission_control_actions, {
            "remove 10",
            "add 2000",
            "add 2001",
            "add 2002",
            "remove 9",
            "remove 8",
        })
        expect.equal(world.notifications, {})
        world.advance(61)
        expect.equal(controller.state.desktop_counts.kept, { ["built-in"] = 3, ["external 1"] = 4 })
    end,

    a_window_that_hammerspoon_has_not_seen_returns_to_the_monitor = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        world.windows[43].is_unseen = true
        world.key_strokes = {}
        world.connect_screen(DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.key_strokes[1], "ctrl+alt+shift+cmd+5")
        expect.equal(world.windows[43].space_id, 2001)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.notifications, {})
    end,

    a_desktop_that_the_user_adds_stays_after_a_monitor_change = function()
        local world, controller = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.advance(61)
        table.insert(world.displays[1].space_ids, 99)
        world.advance(61)
        expect.equal(controller.state.desktop_counts.kept, { ["built-in"] = 4, ["external 1"] = 4 })
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99, 8, 9 })
        expect.equal(world.mission_control_actions, { "remove 10" })
    end,

    desktop_10_is_shown_with_control_0_after_its_shortcut_is_turned_on = function()
        local world = start_two_screen_world({ 3, 14, 64, 65, 66 }, { 7, 8, 9, 10, 11 })
        local result = "pending"
        switch_desktops.switch_to_space(
            11,
            default_settings.create("/fake/state.json").timing,
            function(error_message)
                result = error_message or "shown"
            end
        )
        world.advance(5)
        expect.equal(result, "shown")
        expect.equal(world.displays[2].active_space_id, 11)
        expect.equal(world.key_strokes, { "ctrl+alt+shift+cmd+0" })
        expect.equal(#world.tasks, 1)
    end,

    a_profile_records_a_window_that_hammerspoon_has_not_seen = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.key_strokes = {}
        world.advance(65)
        expect.equal(recorded_sight(controller, 1, reading.id), "in sight")
        local arrangement =
            profile_state.find_arrangement(controller.state, 1, MONITOR_CONFIGURATION_KEY)
        local record = arrangement.windows[#arrangement.windows]
        expect.equal(record.title, "Reading list")
        expect.equal(record.desktop_number, 3)
        expect.equal(record.unit_frame ~= nil, true)
        expect.equal(world.key_strokes, {})
    end,

    a_switch_shows_the_desktop_of_a_window_not_seen_and_minimizes_it = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(65)
        world.key_strokes = {}
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(world.key_strokes, { "ctrl+alt+shift+cmd+3", "ctrl+alt+shift+cmd+1" })
        expect.equal(world.windows[reading.id].is_minimized, true)
        expect.equal(world.displays[1].active_space_id, 3)
        local shown = read_busy_messages(world)
        expect.equal(shown[1], "Finding the windows on other desktops… please wait")
    end,

    a_shortcut_from_the_file_replaces_the_default = function()
        local world = fake_hammerspoon.install({
            screens = { BUILTIN_SCREEN },
            displays = { { uuid = BUILTIN_SCREEN.uuid, space_ids = { 3 }, active_space_id = 3 } },
            applications = {},
            windows = {},
        })
        world.json_files[world.shortcuts_file_path] = {
            ["profiles.toggle.1"] = { modifiers = { "cmd", "alt", "shift" }, key = "a" },
            ["tiling.fill"] = false,
        }
        local shortcuts = shortcut_center.new(world.shortcuts_file_path)
        local controller =
            profile_controller.start(default_settings.create("/fake/state.json"), shortcuts)
        tiling_controller.start(tiling_settings.create(), shortcuts)
        shortcuts:check_overrides()
        expect.equal(world.notifications, {})
        shortcuts.overrides["tiling.nowhere"] = false
        shortcuts:check_overrides()
        expect.equal(#world.notifications, 1)
        shortcuts.overrides["tiling.nowhere"] = nil
        world.notifications = {}
        expect.equal(world.hotkey_by_shortcut["cmd+alt+shift 1"], nil)
        expect.equal(world.hotkey_by_shortcut["ctrl+alt return"], nil)
        expect.equal(world.hotkey_by_shortcut["ctrl+alt left"] ~= nil, true)
        world.hotkey_by_shortcut["cmd+alt+shift a"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.notifications, {})
    end,

    the_window_of_the_shortcuts_records_a_new_shortcut = function()
        local world, controller = start_world()
        find_menu_item(world, "Keyboard shortcuts…").fn()
        local row = find_shortcut_row(controller, "window_search.toggle")
        expect.equal(row.title, "Show the search of the windows, or close it")
        expect.equal(row.macos_conflict, nil)
        world.hotkey_events = {}
        world.post_to_webview({ kind = "record_start" })
        expect.equal(world.hotkey_events[1]:match("^disable") ~= nil, true)
        world.post_to_webview({
            kind = "record",
            id = "window_search.toggle",
            modifiers = { "ctrl", "alt" },
            key = "f",
        })
        expect.equal(controller.shortcut_window.model.pending, nil)
        expect.equal(world.hotkey_by_shortcut[SEARCH_SHORTCUT], nil)
        world.hotkey_by_shortcut["ctrl+alt f"]()
        expect.equal(world.read_search_panel() ~= nil, true)
        expect.equal(find_shortcut_row(controller, "window_search.toggle").is_default, false)
        world.post_to_webview({ kind = "default", id = "window_search.toggle" })
        expect.equal(world.hotkey_by_shortcut["ctrl+alt f"], nil)
        expect.equal(world.hotkey_by_shortcut[SEARCH_SHORTCUT] ~= nil, true)
    end,

    a_shortcut_of_another_action_moves_after_a_choice = function()
        local world, controller = start_world()
        find_menu_item(world, "Keyboard shortcuts…").fn()
        world.post_to_webview({ kind = "record_start" })
        world.post_to_webview({
            kind = "record",
            id = "profiles.deactivate",
            modifiers = { "cmd", "alt", "shift" },
            key = "2",
        })
        local pending = controller.shortcut_window.model.pending
        expect.equal(pending.holder.id, "profiles.toggle.2")
        expect.equal(pending.text, "Option-Shift-Command-2")
        expect.equal(world.hotkey_by_shortcut["cmd+alt+shift 0"] ~= nil, true)
        world.post_to_webview({ kind = "resolve", remove_holder = true })
        expect.equal(controller.shortcut_window.model.pending, nil)
        expect.equal(world.hotkey_by_shortcut["cmd+alt+shift 0"], nil)
        expect.equal(controller.shortcuts:find_shortcut("profiles.toggle.2"), nil)
        expect.equal(controller.shortcuts:find_shortcut("profiles.deactivate").key, "2")
        world.post_to_webview({ kind = "done" })
        expect.equal(controller.shortcut_window, nil)
    end,

    a_shortcut_that_macos_uses_can_turn_the_macos_shortcut_off = function()
        local world, controller = start_world()
        world.symbolic_hotkeys["64"] =
            { enabled = true, value = { parameters = { 32, 49, 1048576 }, type = "standard" } }
        find_menu_item(world, "Keyboard shortcuts…").fn()
        world.post_to_webview({ kind = "record_start" })
        world.post_to_webview({
            kind = "record",
            id = "window_search.toggle",
            modifiers = { "cmd" },
            key = "space",
        })
        expect.equal(controller.shortcut_window.model.pending.macos.name, "Show Spotlight search")
        world.post_to_webview({ kind = "resolve", turn_off_macos = true })
        expect.equal(
            world.tasks[#world.tasks].arguments[1]:match("disable_macos_shortcut%.sh$") ~= nil,
            true
        )
        expect.equal(world.symbolic_hotkeys["64"].enabled, false)
        expect.equal(world.hotkey_by_shortcut["cmd space"] ~= nil, true)
        expect.equal(find_shortcut_row(controller, "window_search.toggle").macos_conflict, nil)
    end,

    a_row_warns_when_macos_uses_its_shortcut_and_control_with_a_digit_is_refused = function()
        local world, controller = start_world()
        world.symbolic_hotkeys["61"] =
            { enabled = true, value = { parameters = { 32, 49, 1835008 }, type = "standard" } }
        find_menu_item(world, "Keyboard shortcuts…").fn()
        expect.equal(
            find_shortcut_row(controller, "window_search.toggle").macos_conflict.name,
            "Select next source in Input menu"
        )
        world.post_to_webview({ kind = "record_start" })
        world.post_to_webview({
            kind = "record",
            id = "window_search.toggle",
            modifiers = { "ctrl", "alt", "shift", "cmd" },
            key = "3",
        })
        expect.equal(controller.shortcut_window.model.pending.is_reserved, true)
        world.post_to_webview({ kind = "resolve", remove_holder = true })
        expect.equal(controller.shortcuts:find_shortcut("window_search.toggle").key, "space")
        expect.equal(world.hotkey_by_shortcut["ctrl+alt+shift+cmd 3"], nil)
    end,

    a_highlight_color_of_the_setting_marks_the_selection = function()
        local selection = { hex = "#2E8B57", alpha = 0.9 }
        local world = start_world({ search_highlight_colors = { selection = selection } })
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        local fill = nil
        for _, element in ipairs(world.overlay.elements) do
            if element.id == "selection" then
                fill = element.fillColor
            end
        end
        expect.equal(fill, selection)
        expect.raises(function()
            start_world({ search_highlight_colors = { selected = selection } })
        end, 'names "selected", which is none of')
    end,

    a_color_from_the_window_of_the_colors_shows_in_the_next_search = function()
        local world, controller = start_world()
        find_menu_item(world, "Search colors…").fn()
        expect.equal(
            controller.color_window.model.colors.selection,
            { hex = "#3373F2", alpha = 0.95 }
        )
        local chosen = controller.color_window.model.colors
        chosen.selection = { hex = "#2E8B57", alpha = 0.9 }
        world.post_to_webview({ kind = "set", colors = chosen })
        expect.equal(world.saved_json.highlight_colors.selection, { hex = "#2E8B57", alpha = 0.9 })
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        local fill = nil
        for _, element in ipairs(world.overlay.elements) do
            if element.id == "selection" then
                fill = element.fillColor
            end
        end
        expect.equal(fill, { hex = "#2E8B57", alpha = 0.9 })
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        world.post_to_webview({ kind = "restore" })
        expect.equal(controller.state.highlight_colors, {})
        world.post_to_webview({ kind = "done" })
        expect.equal(controller.color_window, nil)
    end,

    an_unknown_way_to_match_windows_stops_the_start = function()
        expect.raises(function()
            start_world({ match_windows_by = "guess" })
        end, 'the setting match_windows_by is "guess", which names no way to match windows')
    end,

    the_first_profile_records_the_open_windows = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(recorded_sight(controller, 1, 41), "in sight")
        expect.equal(recorded_sight(controller, 1, 42), "in sight")
        expect.equal(world.window_operations, {})
        expect.equal(world.menubar_title, "◧ 1")
        expect.equal(world.notifications, {})
    end,

    a_new_profile_minimizes_the_windows_of_the_old_one = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(world.windows[41].is_minimized, true)
        expect.equal(world.windows[42].is_minimized, true)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        local arrangement = profile_state.find_arrangement(controller.state, 1, "built-in")
        expect.equal(arrangement.windows[1].desktop_number, 2)
        expect.equal(arrangement.windows[2].desktop_number, 1)
    end,

    the_old_profile_comes_back_on_its_desktops = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 2, news.id), "in sight")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.windows[news.id].is_minimized, true)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[42].is_minimized, false)
        expect.equal(world.windows[42].space_id, 3)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.key_strokes, {})
        expect.equal(world.notifications, {})
    end,

    a_switch_removes_no_desktop_and_presses_no_key_for_windows_in_place = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local arrangement = profile_state.find_arrangement(controller.state, 1, "built-in")
        expect.equal(arrangement.monitors[1].desktop_count, 4)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99 })
        expect.equal(world.key_strokes, {})
        expect.equal(world.notifications, {})
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[42].space_id, 3)
    end,

    the_hiding_setting_hides_an_application_of_the_old_profile = function()
        local world, controller =
            start_world({ concealment_method = concealment_method.HIDE_APPLICATIONS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, true)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, true)
        expect.equal(world.windows[41].is_minimized, false)
    end,

    the_hiding_setting_minimizes_the_other_windows_of_a_shared_application = function()
        local world, controller =
            start_world({ concealment_method = concealment_method.HIDE_APPLICATIONS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 2, news.id), "in sight")
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.windows[41].is_minimized, false)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.windows[news.id].is_minimized, true)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.notifications, {})
    end,

    a_window_that_two_profiles_record_at_the_same_place_is_left_alone = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.unminimize_window(41)
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 2, 41), "in sight")
        expect.equal(recorded_sight(controller, 2, 42), "out of sight")
        world.window_operations = {}
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_operations, { "unminimize 42", "minimize 42" })
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[41].space_id, 14)
    end,

    a_window_gets_the_frame_that_the_profile_entered_recorded = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.unminimize_window(41)
        world.advance(SETTLE_SECONDS)
        local moved_frame = { x = 100, y = 100, w = 600, h = 500 }
        world.windows[41].frame = moved_frame
        world.window_operations = {}
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect_frame_near(world.windows[41].frame, { x = 0, y = 25, w = 720, h = 875 })
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect_frame_near(world.windows[41].frame, moved_frame)
        expect.equal(
            world.window_operations,
            { "setFrame 41", "unminimize 42", "minimize 42", "setFrame 41" }
        )
    end,

    a_window_minimized_by_hand_stays_out_of_sight_in_that_profile = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.unminimize_window(41)
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.minimize_window(41)
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, 41), "out of sight")
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[42].is_minimized, true)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, true)
        expect.equal(world.windows[42].is_minimized, false)
    end,

    a_reopened_window_keeps_its_place_in_every_profile = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        local reopened = world.create_window("com.microsoft.Word", "Draft.docx")
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, reopened.id), "in sight")
        expect.equal(recorded_sight(controller, 1, 42), nil)
        expect.equal(recorded_sight(controller, 2, reopened.id), "in sight")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[reopened.id].is_minimized, false)
        expect.equal(world.windows[41].is_minimized, false)
    end,

    a_window_reopened_while_no_profile_is_active_is_renamed_at_the_next_switch = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["0"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        local reopened = world.create_window("com.microsoft.Word", "Draft.docx")
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, reopened.id), nil)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, reopened.id), "in sight")
        expect.equal(world.windows[reopened.id].is_minimized, true)
    end,

    a_new_window_with_another_title_is_no_reopened_window = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        local other = world.create_window("com.microsoft.Word", "Budget.xlsx")
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, other.id), nil)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[other.id].is_minimized, true)
    end,

    a_window_with_the_id_0_is_not_recorded = function()
        local world, controller = start_world()
        world.windows[0] = nil
        local control_center = world.create_window("com.apple.Safari", "")
        world.windows[control_center.id] = nil
        control_center.id = 0
        world.windows[0] = control_center
        for index, window_id in ipairs(world.window_order) do
            if window_id ~= 41 and window_id ~= 42 then
                world.window_order[index] = 0
            end
        end
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, 0), nil)
        expect.equal(recorded_sight(controller, 1, 41), "in sight")
    end,

    a_window_that_the_filter_drops_while_hidden_comes_back = function()
        local world = start_world({ concealment_method = concealment_method.HIDE_APPLICATIONS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.applications["com.microsoft.Word"].is_dropped_by_filter_while_hidden = true
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, true)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.windows[42].is_minimized, false)
        expect.equal(world.windows[42].space_id, 3)
        expect.equal(world.notifications, {})
    end,

    an_unhide_by_the_user_leaves_the_windows_in_sight_for_the_next_capture = function()
        local world, controller =
            start_world({ concealment_method = concealment_method.HIDE_APPLICATIONS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.unhide_application("com.apple.Safari")
        world.advance(61)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(recorded_sight(controller, 2, 41), "in sight")
    end,

    a_closed_window_gets_a_new_window_on_its_desktop = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(41)
        world.key_strokes = {}
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local opened = find_window_titled(world, "Start Page")
        expect.equal(opened ~= nil, true)
        expect.equal(opened.space_id, 14)
        expect.equal(opened.is_minimized, false)
        expect_frame_near(opened.frame, { x = 0, y = 25, w = 720, h = 875 })
        expect.equal(world.menu_selections, { "com.apple.Safari New Window" })
        expect.equal(world.key_strokes, { "ctrl+alt+shift+cmd+2", "ctrl+alt+shift+cmd+1" })
        expect.equal(recorded_sight(controller, 1, opened.id), "in sight")
        expect.equal(world.notifications, {})
    end,

    a_desktop_without_its_shortcut_gets_it_before_the_press = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(41)
        world.symbolic_hotkeys["119"] = nil
        world.key_strokes = {}
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(#world.tasks, 1)
        expect.equal(
            world.tasks[1].arguments[1]:match("tools/enable_desktop_shortcuts%.sh$") ~= nil,
            true
        )
        expect.equal(world.key_strokes, { "ctrl+alt+shift+cmd+2", "ctrl+alt+shift+cmd+1" })
        expect.equal(world.notifications, {})
    end,

    a_shortcut_that_cannot_be_turned_on_is_reported_without_a_press = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(41)
        world.symbolic_hotkeys["119"] = nil
        world.task_exit_code = 1
        world.key_strokes = {}
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.key_strokes, {})
        local message = "desktop 2 cannot be shown, because its shortcut is off and could not"
        expect.equal(world.notifications[1]:sub(1, #message), message)
        expect.equal(world.alerts[#world.alerts], world.notifications[1])
    end,

    a_window_with_the_recorded_title_is_taken_and_no_window_opens = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["0"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        local reopened = world.create_window("com.microsoft.Word", "Draft.docx")
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.menu_selections, {})
        expect.equal(world.windows[reopened.id].is_minimized, false)
        expect.equal(recorded_sight(controller, 1, reopened.id), "in sight")
    end,

    the_policy_that_opens_new_windows_opens_one_despite_a_window_with_the_title = function()
        local world, controller = start_world({
            match_windows_by = match_windows_by.ID,
            missing_window_policy = missing_window_policy.OPEN_NEW_WINDOW,
        })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        local reopened = world.create_window("com.microsoft.Word", "Draft.docx")
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, reopened.id), nil)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local opened = find_window_titled(world, "Document1")
        expect.equal(opened ~= nil, true)
        expect.equal(opened.is_minimized, false)
        expect.equal(world.windows[reopened.id].is_minimized, true)
        expect.equal(world.notifications, {})
    end,

    an_application_without_the_menu_item_gets_a_reopen = function()
        local world = start_world()
        world.applications["com.microsoft.Word"].new_window_title = nil
        world.applications["com.microsoft.Word"].reopen_title = "Main Window"
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local opened = find_window_titled(world, "Main Window")
        expect.equal(opened ~= nil, true)
        expect.equal(opened.space_id, 3)
        expect.equal(world.notifications, {})
    end,

    an_application_that_opens_no_window_is_reported = function()
        local world = start_world()
        world.applications["com.microsoft.Word"].new_window_title = nil
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.notifications, {
            "Microsoft Word opened no new window after a reopen"
                .. " (1 problems in the Hammerspoon console)",
        })
    end,

    a_window_recorded_out_of_sight_and_closed_gets_no_new_window = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(41)
        world.hotkeys["3"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.menu_selections, {})
    end,

    an_application_that_stays_hidden_is_reported = function()
        local world = start_world({ concealment_method = concealment_method.HIDE_APPLICATIONS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.applications["com.microsoft.Word"].ignores_unhide = true
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, true)
        expect.equal(world.notifications, {
            "Microsoft Word stayed hidden (1 problems in the Hammerspoon console)",
        })
    end,

    a_screen_event_without_a_change_of_screens_restores_nothing = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.alerts, { "Profile 1" })
    end,

    a_screen_of_another_size_restores_the_arrangement = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        local _, visible_while_settling = read_busy_messages(world)
        expect.equal(visible_while_settling, 1)
        world.advance(SETTLE_SECONDS)
        local shown, visible_count = read_busy_messages(world)
        expect.equal(shown, {
            "Monitors changed, waiting for macOS… please wait",
            "Arranging Profile 1 for built-in… please wait",
        })
        expect.equal(visible_count, 0)
        expect.equal(world.alerts, { "Profile 1" })
    end,

    a_monitor_configuration_new_to_the_profile_is_left_to_macos = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.screens[1].name = "LG TV SSCR2"
        world.screens[1].frame = { x = 0, y = 25, w = 1872, h = 1053 }
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        local shown, visible_count = read_busy_messages(world)
        expect.equal(shown, { "Monitors changed, waiting for macOS… please wait" })
        expect.equal(visible_count, 0)
        expect.equal(world.alerts, {
            "Profile 1",
            "Profile 1 has no layout for 1 external yet, so the windows stay where macOS put them",
        })
    end,

    a_switch_to_a_recorded_profile_shows_a_message_until_it_ends = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        local _, visible_while_switching = read_busy_messages(world)
        expect.equal(visible_while_switching, 1)
        world.advance(SETTLE_SECONDS)
        local shown, visible_count = read_busy_messages(world)
        expect.equal(shown, { "Arranging Profile 1… please wait" })
        expect.equal(visible_count, 0)
        expect.equal(world.alerts, { "Profile 1", "Profile 2" })
    end,

    a_number_brings_its_application_and_the_next_press_its_next_window = function()
        local world, controller = start_world()
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local entries = profile_state.profile_or_default(controller.state, 1).app_numbers
        expect.equal(entries[1].bundle_id, "com.apple.Safari")
        expect.equal(entries[2].bundle_id, "com.microsoft.Word")
        world.key_strokes = {}
        world.app_hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.displays[1].active_space_id, 14)
        world.app_hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, news.id)
        expect.equal(world.displays[1].active_space_id, 3)
        world.app_hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
        expect.equal(
            world.key_strokes,
            { "ctrl+alt+shift+cmd+2", "ctrl+alt+shift+cmd+1", "ctrl+alt+shift+cmd+2" }
        )
    end,

    a_held_press_shows_the_list_and_the_release_goes_to_the_selection = function()
        local world = start_world({ list_layout = list_layout.ROWS })
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.read_overlay(), nil)
        expect.equal(world.focused_window_id, news.id)
    end,

    a_press_of_another_number_selects_its_application_and_escape_closes_the_list = function()
        local world = start_world({ list_layout = list_layout.ROWS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        expect.equal(world.read_overlay()[2], ">Draft.docx")
        world.app_hotkeys["2"]()
        expect.equal(world.read_overlay()[4], ">Inbox")
        world.press_escape()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.read_overlay(), nil)
        expect.equal(world.focused_window_id, nil)
        world.release_modifiers()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, nil)
    end,

    the_setting_for_snapshots_shows_blurred_previews_and_icons_without_them = function()
        local world = start_world({
            preview_method = preview_method.BLURRED_SNAPSHOTS,
            preview_blur = 2,
            list_layout = list_layout.ROWS,
            list_sizing = list_sizing.FIXED,
            preview_size = { w = 0.04, h = 0.04 },
        })
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.minimize_window(42)
        world.advance(SETTLE_SECONDS)
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
        local world = start_world({
            preview_method = preview_method.BLURRED_SNAPSHOTS,
            preview_blur = 4,
            list_sizing = list_sizing.FIXED,
            preview_size = { w = 0.04, h = 0.04 },
        })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(1)
        expect.equal(world.rendered_sizes[41], { w = 29, h = 14 })
    end,

    the_settings_of_size_set_the_previews_and_the_fonts_of_the_list = function()
        local world = start_world({
            preview_method = preview_method.BLURRED_SNAPSHOTS,
            preview_blur = 1,
            preview_size = { w = 0.05, h = 0.05 },
            list_font_size = 0.02,
            list_layout = list_layout.ROWS,
            list_sizing = list_sizing.FIXED,
        })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
        local world = start_world()
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, news.id)
    end,

    the_columns_per_display_name_each_display_above_its_columns = function()
        local world = start_world({ list_layout = list_layout.COLUMNS_PER_DISPLAY })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
        local world = start_world({ preview_size = { w = 0.1, h = 0.3 } })
        for index = 1, 6 do
            world.create_window("com.apple.Safari", "Tab " .. index)
        end
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        local frame = world.overlay.current_frame
        expect.equal(frame.h <= 0.9 * 875 + 0.5, true)
        expect.equal(frame.y >= 25, true)
    end,

    filling_the_screen_grows_a_short_list_and_fixed_sizes_keep_the_settings = function()
        local function read_first_preview_width(setting_changes)
            local world = start_world(setting_changes)
            world.hotkeys["1"]()
            world.advance(SETTLE_SECONDS)
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
        local world = start_world()
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
        world.advance(SETTLE_SECONDS)
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
            local world = start_world({
                list_sizing = list_sizing.FIXED,
                list_font_size = 0.016,
                title_overflow = title_overflow.WRAP,
                title_line_count = line_limit,
            })
            world.create_window("com.apple.Safari", long_title)
            world.hotkeys["1"]()
            world.advance(SETTLE_SECONDS)
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
        expect.equal(two_lines.text:match("…$") ~= nil, true)
    end,

    the_selected_title_scrolls_and_the_scrolling_stops_with_the_list = function()
        local long_title = "A very long title of a window that does not fit its column at all"
        local world = start_world({
            list_sizing = list_sizing.FIXED,
            title_overflow = title_overflow.SCROLL,
        })
        local long_window = world.create_window("com.apple.Safari", long_title)
        world.create_window("com.apple.Safari", "Another very long title that the list shortens")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
            return nil
        end
        expect.equal(world.read_overlay()[3]:sub(1, 1), ">")
        local scrolling = find_text("A very")
        expect.equal(scrolling.text:match("…$"), nil)
        expect.equal(find_text("Another").text:match("…$") ~= nil, true)
        local first_line = world.read_overlay()[3]
        world.advance(2)
        local later_line = world.read_overlay()[3]
        expect.equal(later_line:sub(1, 1), ">")
        expect.equal(later_line ~= first_line, true)
        world.release_modifiers()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, long_window.id)
        expect.equal(retained_timers.count_running(), timers_before)
    end,

    a_slow_snapshot_stops_the_snapshots_until_a_reload = function()
        local world = start_world({ preview_method = preview_method.BLURRED_SNAPSHOTS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.snapshot_seconds = 2
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(1)
        expect.equal(world.snapshot_count, 1)
        expect.equal(world.read_overlay_images(), {
            "icon com.microsoft.Word",
            "icon com.microsoft.Word",
            "icon com.apple.Safari",
            "icon com.apple.Safari",
        })
        world.release_modifiers()
        world.advance(SETTLE_SECONDS)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["1"]()
        world.advance(1)
        expect.equal(world.snapshot_count, 1)
    end,

    a_window_of_an_unticked_application_stays_and_is_not_recorded = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, 41), "in sight")
        open_app_pool_window(world)
        world.post_to_webview({
            kind = "tick",
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            is_listed = true,
        })
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, 41), nil)
        expect.equal(recorded_sight(controller, 1, 42), "in sight")
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[42].is_minimized, true)
    end,

    the_window_of_the_pool_takes_several_ticks_and_a_change_of_mode = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        open_app_pool_window(world)
        expect.equal(world.webview.is_visible, true)
        expect.equal(
            world.webview.page:find('data-app-name="Safari"> Safari', 1, true) ~= nil,
            true
        )
        world.post_to_webview({ kind = "mode", mode = "manage_listed" })
        for _, application in ipairs({
            { "com.apple.Safari", "Safari" },
            { "com.microsoft.Word", "Microsoft Word" },
        }) do
            world.post_to_webview({
                kind = "tick",
                bundle_id = application[1],
                app_name = application[2],
                is_listed = true,
            })
        end
        expect.equal(world.webview.is_visible, true)
        expect.equal(controller.state.app_pool.mode, "manage_listed")
        expect.equal(#controller.state.app_pool.manage_listed, 2)
        expect.equal(controller.state.app_pool.skip_listed, {})
        world.post_to_webview({ kind = "mode", mode = "skip_listed" })
        expect.equal(world.webview.page:find('data-app-name="Safari" checked', 1, true), nil)
        world.post_to_webview({ kind = "done" })
        expect.equal(world.webview.is_visible, false)
        expect.equal(controller.app_pool_window, nil)
    end,

    the_menu_offers_each_recorded_profile_to_clear = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local clear_items = find_menu_item(world, "Clear profile").menu
        expect.equal(clear_items[1].disabled, false)
        expect.equal(clear_items[2].disabled, true)
    end,

    clearing_a_profile_after_the_confirmation_removes_its_layouts = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "clear", profile = "1" }
        )
        expect.equal(profile_state.has_arrangements(controller.state, 1), true)
        world.alert_button = "Clear"
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "clear", profile = "1" }
        )
        expect.equal(profile_state.has_arrangements(controller.state, 1), false)
        expect.equal(world.alerts[#world.alerts], "Profile 1 is cleared")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.alerts[#world.alerts], "Profile 1")
        expect.equal(world.windows[42].is_minimized, true)
    end,

    a_number_reaches_a_window_that_another_profile_recorded = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, true)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "5", app = "Safari" }
        )
        world.app_hotkeys["5"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.focused_window_id, 41)
    end,

    a_number_of_an_application_without_a_window_opens_one = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "4", app = "com.microsoft.Word" }
        )
        world.app_hotkeys["4"]()
        world.advance(SETTLE_SECONDS)
        local opened = find_window_titled(world, "Document1")
        expect.equal(opened ~= nil, true)
        expect.equal(world.focused_window_id, opened.id)
    end,

    a_number_without_an_application_passes_its_keys_through = function()
        local world = start_world()
        world.app_hotkeys["7"]()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "1", app = "Microsoft Word" }
        )
        world.advance(61)
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
        local world, controller = start_world()
        world.advance(SETTLE_SECONDS)
        local entries = profile_state.profile_or_default(controller.state, 0).app_numbers
        expect.equal(entries[1].bundle_id, "com.microsoft.Word")
        expect.equal(entries[2].bundle_id, "com.apple.Safari")
        expect.equal(
            profile_state.find_arrangement(controller.state, 0, MONITOR_CONFIGURATION_KEY),
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
        expect.equal(controller.state.active_profile_number, nil)
    end,

    deactivating_a_profile_gives_profile_0_its_numbers_at_once = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        controller.state = profile_state.with_app_numbers(controller.state, 0, {})
        world.hotkeys["0"]()
        local entries = profile_state.profile_or_default(controller.state, 0).app_numbers
        expect.equal(#entries, 2)
    end,

    a_number_chosen_while_no_profile_is_active_goes_to_profile_0 = function()
        local world, controller = start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "5", app = "Safari" }
        )
        expect.equal(world.alerts[#world.alerts], "Safari is number 5 in Profile 0")
        expect.equal(world.notifications, {})
        world.app_hotkeys["5"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
        expect.equal(profile_state.profile_or_default(controller.state, 1).app_numbers, {})
    end,

    control_option_0_returns_every_number_of_the_active_profile_to_the_default = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
        local world, controller = start_world()
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
        local world, controller = start_world()
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
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 41)
    end,

    numbering_an_application_that_is_not_running_is_reported = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "3", app = "Notes" }
        )
        expect.equal(world.notifications, { 'No running application is named "Notes"' })
    end,

    the_same_key_on_the_active_profile_deactivates_it = function()
        local world, controller = start_world()
        world.hotkeys["3"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["3"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, nil)
        expect.equal(world.menubar_title, "◧")
    end,

    an_application_that_is_not_running_is_launched = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local shopping = world.create_window("com.apple.Notes", "Shopping")
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.windows[shopping.id] = nil
        for index, window_id in ipairs(world.window_order) do
            if window_id == shopping.id then
                table.remove(world.window_order, index)
            end
        end
        world.applications["com.apple.Notes"].is_running = false
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local relaunched = nil
        for _, window in pairs(world.windows) do
            if window.title == "Shopping" then
                relaunched = window
            end
        end
        expect.equal(relaunched ~= nil, true)
        expect.equal(recorded_sight(controller, 1, relaunched.id), "in sight")
        expect.equal(relaunched.is_minimized, false)
    end,

    a_url_renames_a_profile = function()
        local world, controller = start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "rename", profile = "4", name = "Writing" }
        )
        expect.equal(profile_state.profile_or_default(controller.state, 4).name, "Writing")
    end,

    a_url_deactivates_a_named_profile_only_while_it_is_active = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "deactivate", profile = "2" }
        )
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.alerts[#world.alerts], "Profile 2 is not active")
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "deactivate", profile = "1" }
        )
        expect.equal(controller.state.active_profile_number, nil)
    end,

    a_bad_url_is_reported = function()
        local world = start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "activate", profile = "11" }
        )
        expect.equal(world.notifications, { 'the profile "11" is not a number from 1 to 9' })
    end,

    the_search_shows_every_window_above_the_applications = function()
        local world = start_world()
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.focused_window_id = news.id
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
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
        local world = start_world()
        local news = world.create_window("com.apple.Safari", "News")
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.read_search_panel(), nil)
        expect.equal(world.focused_window_id, news.id)
    end,

    hovering_over_an_application_shows_its_windows_and_a_click_on_one_reaches_it = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.read_search_panel(), nil)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.displays[1].active_space_id, 14)
    end,

    a_click_chooses_an_application_until_typing = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.read_search_panel(), nil)
        expect.equal(world.focused_window_id, nil)
    end,

    the_search_reaches_a_window_on_a_desktop_not_visited = function()
        local world = start_world()
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(SETTLE_SECONDS)
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        world.type_keys("read")
        world.advance(0)
        expect.equal(world.read_search_panel().windows, { "selection Reading list | Safari" })
        world.press_key("return")
        world.advance(SETTLE_SECONDS)
        expect.equal(world.key_strokes, { "ctrl+alt+shift+cmd+3" })
        expect.equal(world.focused_window_id, reading.id)
    end,

    a_window_found_after_the_panel_opened_joins_it = function()
        local world = start_world()
        world.advance(SETTLE_SECONDS)
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        expect.equal(#world.read_search_panel().windows, 2)
        world.advance(1)
        expect.equal(world.read_search_panel().windows[3], "plain Reading list | Safari")
    end,

    the_numbered_list_holds_a_window_on_a_desktop_not_visited = function()
        local world = start_world({ list_layout = list_layout.ROWS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(2 * SETTLE_SECONDS + 1)
        world.key_strokes = {}
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.key_strokes, { "ctrl+alt+shift+cmd+3" })
        expect.equal(world.focused_window_id, reading.id)
    end,

    the_arrows_move_the_selection_in_the_grid_of_the_previews = function()
        local world = start_world()
        world.create_window("com.apple.Safari", "News")
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
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
        local world = start_world({ list_font_size = 0.01 })
        for _, title in ipairs({ "News", "Weather", "Maps" }) do
            world.create_window("com.apple.Safari", title)
        end
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
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
        local world = start_world()
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        expect.equal(world.read_search_panel() ~= nil, true)
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        expect.equal(world.read_search_panel(), nil)
        world.type_keys("x")
        world.advance(SETTLE_SECONDS)
        expect.equal(world.read_search_panel(), nil)
    end,

    return_without_a_match_keeps_the_search = function()
        local world = start_world()
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        world.type_keys("zz")
        world.press_key("return")
        world.advance(SETTLE_SECONDS)
        local panel = world.read_search_panel()
        expect.equal(panel.line[2], "no window matches")
        expect.equal(panel.note, "No window matches")
    end,

    a_url_opens_the_search = function()
        local world = start_world()
        world.url_handlers["desktop-manager"]("desktop-manager", { action = "search-windows" })
        expect.equal(world.read_search_panel().line[2], "2 windows")
    end,
}
