local app_switcher = require("desktop_manager.macos.app_switcher")
local concealment_method = require("desktop_manager.core.concealment_method")
local default_settings = require("desktop_manager.default_settings")
local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")
local list_layout = require("desktop_manager.core.list_layout")
local list_sizing = require("desktop_manager.core.list_sizing")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local preview_method = require("desktop_manager.core.preview_method")
local unmatched_window_action = require("desktop_manager.core.unmatched_window_action")
local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local mission_control_desktops = require("desktop_manager.macos.mission_control_desktops")
local profile_controller = require("desktop_manager.macos.profile_controller")
local profile_state = require("desktop_manager.core.profile_state")
local retained_timers = require("desktop_manager.macos.retained_timers")
local shortcut_center = require("keyboard_shortcuts.macos.shortcut_center")
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
---@param saved_state table|nil the state file that the desktop manager finds at its start
---@return table world
---@return ProfileController controller
local function start_world(setting_changes, saved_state)
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
    world.saved_json = saved_state
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

---The world of `start_two_screen_world` with Safari in front on the built-in display, and the
---Microsoft Word window "Notes.docx", which Word focused last, on the desktop that the Dell monitor
---shows.
---Each press takes effect after about one second, and the fake models the bounce shortly after.
---@return table world
---@return table notes the window "Notes.docx"
local function start_bounce_world()
    local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
    local news = world.add_window_of("com.apple.Safari", "News", 3)
    local notes = world.add_window_of("com.microsoft.Word", "Notes.docx", 7)
    world.focused_window_id = news.id
    world.applications["com.microsoft.Word"].focused_window_id = notes.id
    world.desktop_press_delay_seconds = 1.01
    world.bounce_delay_seconds = 0.02
    return world, notes
end

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

---@param world table
local function leave_notes_to_macos(world)
    open_app_pool_window(world)
    world.post_to_webview({
        kind = "tick",
        bundle_id = "com.apple.Notes",
        app_name = "Notes",
        is_listed = true,
    })
end

---Puts a window of Notes, which the desktop manager leaves to macOS, on a desktop beyond the 3
---desktops of profile 1 while profile 2 is active, changes the window as `change_window` does, and
---switches to profile 1.
---@param change_window fun(world: table, window: table)
---@return table world
---@return table window the window of Notes
local function switch_with_a_window_left_to_macos(change_window)
    local world = start_world()
    world.hotkeys["1"]()
    world.advance(SETTLE_SECONDS)
    world.hotkeys["2"]()
    world.advance(SETTLE_SECONDS)
    leave_notes_to_macos(world)
    world.displays[1].space_ids = { 3, 14, 64, 99 }
    local shopping = world.add_window_of("com.apple.Notes", "Shopping", 99)
    change_window(world, shopping)
    world.advance(61)
    world.hotkeys["1"]()
    world.advance(SETTLE_SECONDS)
    return world, shopping
end

---Makes the desktops unreadable once Mission Control opens, so that the step that runs then raises
---and leaves Mission Control open.
---@param world table
local function make_desktops_unreadable_once_mission_control_opens(world)
    world.on_mission_control_open = function()
        world.desktop_read_error = "macOS stopped answering"
    end
end

---@param controller ProfileController
---@param window_id integer
---@return WindowRecord|nil the record of the window in profile 1 for the built-in display alone
local function find_record_of_profile_1(controller, window_id)
    local arrangement =
        profile_state.find_arrangement(controller.state, 1, MONITOR_CONFIGURATION_KEY)
    for _, record in ipairs(arrangement and arrangement.windows or {}) do
        if record.window_id == window_id then
            return record
        end
    end
    return nil
end

local WATCHDOG_MESSAGE = "Desktop Manager stopped a switch that did not finish within 90 seconds"
    .. " (1 problems in the Hammerspoon console)"

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
    local world, controller = start_world({
        hidden_application_windows = setting,
        list_layout = list_layout.ROWS,
    })
    local notes = world.add_window_of("com.microsoft.Word", "Notes.docx", 64)
    world.hotkeys["1"]()
    world.advance(SETTLE_SECONDS)
    world.applications["com.microsoft.Word"].is_dropped_by_filter_while_hidden = true
    world.hide_application("com.microsoft.Word")
    world.hide_application("com.apple.Safari")
    world.advance(61)
    return world, controller, notes
end

---Runs an action and returns the lines that the tools wrote to the console during it.
---@param world table
---@param action fun()
---@return string[]
local function record_log_lines(world, action)
    local first_index = #world.log_lines + 1
    action()
    return { table.unpack(world.log_lines, first_index) }
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
    world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
    world.advance(1)
    return world.read_search_panel().windows
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
        expect.equal(world.mission_control_openings, 3)
        expect.equal(world.window_moves, { "41 to 3", "43 to 3", "41 to 2000", "43 to 2001" })
        expect.equal(world.frames_set_out_of_view, {})
        expect.equal(world.is_mission_control_open, false)
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
        world.mission_control_actions = {}
        world.connect_screen(DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_moves, { "43 to 3", "41 to 3", "41 to 2000", "43 to 2001" })
        expect.equal(
            world.mission_control_actions,
            { "add 2000", "add 2001", "add 2002", "remove 9", "remove 8" }
        )
        expect.equal(world.frames_set_out_of_view, {})
        expect.equal(world.key_strokes, {})
        expect.equal(world.windows[43].space_id, 2001)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.notifications, {})
    end,

    a_switch_shows_the_desktop_that_each_screen_showed = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.displays[1].active_space_id = 14
        world.displays[2].active_space_id = 9
        world.focused_display_uuid = BUILTIN_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.displays[2].active_space_id = 7
        world.focused_display_uuid = DELL_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 9", "show 14" })
        expect.equal(world.mission_control_openings, 2)
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.displays[2].active_space_id, 9)
        expect.equal(world.focused_display_uuid, BUILTIN_SCREEN.uuid)
        local shown = read_busy_messages(world)
        expect.equal(shown[#shown - 2], "Showing desktop 3 of external 1… please wait")
        expect.equal(shown[#shown], "Showing desktop 2 of built-in… please wait")
        expect.equal(world.notifications, {})
    end,

    a_switch_ends_with_the_focus_on_the_screen_that_had_it = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.displays[1].active_space_id = 14
        world.displays[2].active_space_id = 8
        world.focused_display_uuid = DELL_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.focused_display_uuid = BUILTIN_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 14" })
        expect.equal(world.focused_display_uuid, DELL_SCREEN.uuid)
        expect.equal(world.focused_window_id, 41)
    end,

    a_saved_state_of_the_first_version_shows_its_desktop_without_the_moved_desktops = function()
        local saved_state = {
            format_version = 1,
            monitor_matching = "by_count",
            desktop_counts = { kept = { ["built-in"] = 3 } },
            profiles = {
                ["1"] = {
                    number = 1,
                    arrangements = {
                        ["built-in"] = {
                            monitor_configuration_key = "built-in",
                            monitors = { { slot_key = "built-in", desktop_count = 5 } },
                            focus = { slot_key = "built-in", desktop_number = 3 },
                            windows = {
                                {
                                    window_id = 41,
                                    bundle_id = "com.apple.Safari",
                                    app_name = "Safari",
                                    title = "Inbox",
                                    slot_key = "built-in",
                                    desktop_number = 2,
                                    unit_frame = { x = 0, y = 0, w = 0.5, h = 1 },
                                    is_out_of_sight = false,
                                },
                            },
                        },
                    },
                },
            },
        }
        local world, controller = start_world(nil, saved_state)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 64" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.displays[1].active_space_id, 64)
        local arrangement =
            profile_state.find_arrangement(controller.state, 1, MONITOR_CONFIGURATION_KEY)
        expect.equal(arrangement.monitors, {
            { slot_key = "built-in", desktop_count = 3, shown_desktop_number = 3 },
        })
        expect.equal(world.saved_json.format_version, 2)
        expect.equal(world.notifications, {})
    end,

    a_switch_removes_the_empty_desktops_beyond_the_profile_and_adds_them_back = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 98, 99 }
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.mission_control_actions, { "remove 99", "remove 98" })
        expect.equal(world.mission_control_openings, 1)
        local shown = read_busy_messages(world)
        expect.equal(shown[#shown], "Removing 2 empty desktops from built-in… please wait")
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 2000, 2001 })
        shown = read_busy_messages(world)
        expect.equal(shown[#shown - 1], "Adding 2 desktops to built-in… please wait")
        expect.equal(shown[#shown], "Arranging Profile 2… please wait")
        expect.equal(world.windows_moved_by_removal, {})
        expect.equal(world.notifications, {})
    end,

    a_window_left_to_macos_keeps_its_desktop_beyond_the_profile_in_sight = function()
        local world, shopping = switch_with_a_window_left_to_macos(function() end)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99 })
        expect.equal(world.windows[shopping.id].space_id, 99)
        expect.equal(world.mission_control_actions, {})
    end,

    a_minimized_window_left_to_macos_keeps_its_desktop_beyond_the_profile = function()
        local world, shopping = switch_with_a_window_left_to_macos(function(world, window)
            world.minimize_window(window.id)
        end)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99 })
        expect.equal(world.windows[shopping.id].space_id, 99)
        expect.equal(world.mission_control_actions, {})
    end,

    a_window_of_a_hidden_application_left_to_macos_keeps_its_desktop_beyond_the_profile = function()
        local world, shopping = switch_with_a_window_left_to_macos(function(world)
            world.applications["com.apple.Notes"].is_hidden = true
        end)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 99 })
        expect.equal(world.windows[shopping.id].space_id, 99)
        expect.equal(world.mission_control_actions, {})
    end,

    a_window_that_a_hidden_application_keeps_ordered_out_keeps_no_desktop = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        leave_notes_to_macos(world)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        local closed = world.create_unseen_window("com.apple.Notes", "New Note", 99)
        world.windows[closed.id].is_ordered_out = true
        world.applications["com.apple.Notes"].is_hidden = true
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    a_window_that_its_application_keeps_ordered_out_keeps_no_desktop_beyond_the_profile = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        leave_notes_to_macos(world)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        local closed = world.create_unseen_window("com.apple.Notes", "New Note", 99)
        world.windows[closed.id].is_ordered_out = true
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    a_window_of_a_managed_application_that_the_switch_hides_keeps_no_desktop = function()
        local world = start_world({ concealment_method = concealment_method.HIDE_APPLICATIONS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.add_window_of("com.apple.Notes", "Shopping", 99)
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.applications["com.apple.Notes"].is_hidden, true)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.windows_moved_by_removal, {})
    end,

    a_window_on_every_desktop_keeps_none_of_them = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        leave_notes_to_macos(world)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        local sticky = world.add_window_of("com.apple.Notes", "Sticky", 99)
        world.windows[sticky.id].is_on_every_desktop = true
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    a_minimized_window_keeps_no_desktop_beyond_the_profile = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.displays[1].active_space_id = 99
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[news.id].is_minimized, true)
        expect.equal(world.mission_control_actions, { "remove 99" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.windows[news.id].space_id, 3)
        expect.equal(world.windows_moved_by_removal, {})
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 2000 })
        expect.equal(world.windows[news.id].space_id, 2000)
        expect.equal(world.windows[news.id].is_minimized, false)
        expect.equal(world.window_moves, { news.id .. " to 2000" })
        expect.equal(world.mission_control_actions, { "remove 99", "add 2000" })
        expect.equal(world.notifications, {})
    end,

    the_desktop_in_view_beyond_the_profile_goes_after_the_recorded_desktop_shows = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.displays[1].active_space_id = 99
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 3", "remove 99" })
        expect.equal(world.mission_control_openings, 2)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    a_desktop_in_view_beyond_the_profile_goes_when_the_profile_records_no_shown_desktop = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        local arrangement = controller.state.profiles["1"].arrangements[MONITOR_CONFIGURATION_KEY]
        arrangement.monitors[1].shown_desktop_number = nil
        arrangement.focused_slot_key = nil
        world.displays[1].space_ids = { 3, 14, 64, 99 }
        world.displays[1].active_space_id = 99
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 64", "remove 99" })
        expect.equal(world.displays[1].active_space_id, 64)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
    end,

    a_window_that_no_profile_recorded_is_minimized_by_a_profile_with_a_layout = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["0"]()
        world.advance(SETTLE_SECONDS)
        local notes = world.create_window("com.microsoft.Word", "Notes.docx")
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[notes.id].is_minimized, true)
        expect.equal(recorded_sight(controller, 1, notes.id), "out of sight")
        world.hotkeys["0"]()
        world.advance(SETTLE_SECONDS)
        local budget = world.create_window("com.microsoft.Word", "Budget.docx")
        world.advance(SETTLE_SECONDS)
        world.hotkeys["3"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[budget.id].is_minimized, false)
        expect.equal(world.windows[42].is_minimized, true)
    end,

    a_restore_after_a_change_of_monitors_minimizes_no_window = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(61)
        world.connect_screen(DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[news.id].is_minimized, false)
        expect.equal(world.windows[41].space_id, 2000)
        expect.equal(world.notifications, {})
    end,

    a_window_on_another_screen_moves_by_its_frame_and_its_id_without_a_desktop_switch = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.windows[41].space_id = 3
        world.windows[41].frame = { x = 0, y = 25, w = 600, h = 400 }
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[41].space_id, 8)
        expect_frame_near(world.windows[41].frame, { x = 1440, y = 25, w = 1280, h = 1390 })
        expect.equal(world.window_moves, { "41 to 8" })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.frames_set_out_of_view, {})
        expect.equal(world.notifications, {})
    end,

    a_window_that_stays_off_its_screen_is_not_moved_by_its_id = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.windows[41].space_id = 3
        world.windows[41].frame = { x = 0, y = 25, w = 600, h = 400 }
        world.frame_refusing_window_ids[41] = true
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[41].space_id, 3)
        expect.equal(world.window_moves, {})
        expect.equal(world.notifications, {
            'Safari window "Inbox" stayed off screen external 1'
                .. " (1 problems in the Hammerspoon console)",
        })
    end,

    a_new_window_for_another_screen_goes_there_without_a_desktop_switch = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.applications["com.apple.Safari"].new_window_title = "Start Page"
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(41)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local opened = find_window_titled(world, "Start Page")
        expect.equal(opened.space_id, 8)
        expect_frame_near(opened.frame, { x = 1440, y = 25, w = 1280, h = 1390 })
        expect.equal(world.window_moves, { opened.id .. " to 8" })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.notifications, {})
    end,

    an_unseen_window_in_place_is_not_moved_at_a_switch = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(65)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_moves, {})
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.windows[reading.id].is_unseen, true)
        expect.equal(world.menu_selections, {})
        expect.equal(world.notifications, {})
    end,

    mission_control_opens_once_for_the_additions_of_two_screens = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14 }
        world.displays[2].space_ids = { 7, 8, 9 }
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "add 2000", "add 2001" })
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.displays[1].space_ids, { 3, 14, 2000 })
        expect.equal(world.displays[2].space_ids, { 7, 8, 9, 2001 })
        local shown = read_busy_messages(world)
        expect.equal(shown[#shown - 2], "Adding 2 desktops… please wait")
    end,

    a_switch_while_a_window_shows_in_full_screen_shows_a_desktop_first = function()
        local world = start_world()
        world.displays[1].full_screen_space_ids = { 500 }
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].active_space_id = 500
        world.windows[42].frame = { x = 100, y = 100, w = 600, h = 500 }
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 3" })
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[42].space_id, 3)
        expect_frame_near(world.windows[42].frame, { x = 720, y = 25, w = 720, h = 875 })
        expect.equal(world.frames_set_out_of_view, {})
        expect.equal(world.notifications, {})
    end,

    a_monitor_change_during_a_switch_is_restored_after_the_switch = function()
        local timing = default_settings.create("/fake/state.json").timing
        timing.screen_settle_seconds = 0.5
        local world, controller = start_world({ timing = timing })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(0.6)
        expect.equal(controller.is_busy, true)
        world.advance(SETTLE_SECONDS)
        local shown = read_busy_messages(world)
        expect.equal(shown[#shown], "Arranging Profile 1 for built-in… please wait")
        expect.equal(controller.is_busy, false)
        expect.equal(controller.are_saves_suspended, false)
        expect_frame_near(world.windows[42].frame, { x = 756, y = 25, w = 756, h = 957 })
    end,

    a_step_that_raises_ends_the_switch_with_a_failure = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.swallows_timer_errors = true
        world.hotkeys["1"]()
        world.desktop_read_error = "macOS stopped answering"
        world.advance(60)
        expect.equal(controller.is_busy, true)
        world.advance(40)
        expect.equal(controller.is_busy, false)
        expect.equal(#world.timer_errors > 0, true)
        local message = "Desktop Manager stopped a switch that did not finish within 90 seconds"
            .. " (1 problems in the Hammerspoon console)"
        expect.equal(world.notifications, { message })
        local _, visible_count = read_busy_messages(world)
        expect.equal(visible_count, 0)
    end,

    a_save_during_a_switch_records_nothing_until_its_end = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.url_handlers["desktop-manager"]("desktop-manager", { action = "save" })
        expect.equal(recorded_sight(controller, 1, 41), "in sight")
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 1, 41), "in sight")
        expect.equal(world.windows[41].is_minimized, false)
    end,

    a_window_reopened_on_a_desktop_not_visited_takes_over_its_records = function()
        local world, controller = start_world({ match_windows_by = match_windows_by.ID })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["0"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(recorded_sight(controller, 2, 42), "out of sight")
        world.close_window(42)
        local reopened = world.create_unseen_window("com.microsoft.Word", "Draft.docx", 64)
        world.advance(61)
        world.hotkeys["1"]()
        world.advance(0.5)
        expect.equal(controller.is_busy, true)
        expect.equal(recorded_sight(controller, 2, reopened.id), "out of sight")
        expect.equal(recorded_sight(controller, 2, 42), nil)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[reopened.id].space_id, 3)
        expect.equal(world.windows[reopened.id].is_minimized, false)
        expect.equal(world.menu_selections, {})
    end,

    the_hiding_setting_reaches_no_window_of_an_application_that_it_hides = function()
        local world = start_world({ concealment_method = concealment_method.HIDE_APPLICATIONS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(65)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, true)
        expect.equal(world.window_moves, {})
        expect.equal(world.windows[reading.id].is_unseen, true)
    end,

    a_desktop_that_the_user_adds_stays_after_a_monitor_change = function()
        local world, controller = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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

    mission_control_opens_once_for_the_removals_and_the_last_press = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].active_space_id = 14
        world.advance(61)
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.displays[1].active_space_id = 3
        world.mission_control_actions = {}
        world.mission_control_openings = 0
        world.connect_screen(DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {
            "add 2000",
            "add 2001",
            "add 2002",
            "remove 9",
            "remove 8",
            "show 14",
        })
        expect.equal(world.mission_control_openings, 2)
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.notifications, {})
        local shown = read_busy_messages(world)
        expect.equal(shown[#shown], "Removing 2 empty desktops from built-in… please wait")
    end,

    an_extra_desktop_in_view_on_the_screen_of_the_focus_goes_after_its_own_opening = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].active_space_id = 9
        world.mission_control_actions = {}
        world.connect_screen(DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {
            "add 2000",
            "add 2001",
            "add 2002",
            "show 3",
            "remove 9",
            "remove 8",
        })
        expect.equal(world.displays[1].space_ids, { 3, 14, 64 })
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.windows[43].space_id, 2001)
        expect.equal(world.notifications, {})
    end,

    a_window_keeps_its_desktop_from_a_removal_while_in_sight_or_left_to_macos = function()
        local world, controller = start_world()
        expect.equal(controller:does_window_keep_desktop(41), true)
        world.minimize_window(41)
        expect.equal(controller:does_window_keep_desktop(41), false)
        world.minimize_window(42)
        open_app_pool_window(world)
        world.post_to_webview({
            kind = "tick",
            bundle_id = "com.microsoft.Word",
            app_name = "Microsoft Word",
            is_listed = true,
        })
        expect.equal(controller:does_window_keep_desktop(42), true)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        expect.equal(controller:does_window_keep_desktop(reading.id), false)
        expect.equal(controller:does_window_keep_desktop(999), false)
    end,

    a_monitor_change_without_an_active_profile_leaves_everything_to_macos = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.advance(61)
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        world.connect_screen(DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 8, 9, 10 })
        expect.equal(world.alerts, {})
        expect.equal(world.notifications, {})
    end,

    a_profile_deactivated_while_the_monitors_settle_leaves_everything_to_macos = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.hotkeys["0"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 8, 9, 10 })
    end,

    a_desktop_after_the_tenth_shows_through_mission_control = function()
        local world = start_two_screen_world({ 3, 14, 64, 65, 66 }, { 7, 8, 9, 10, 11, 12 })
        local result = "pending"
        mission_control_desktops.show_space(
            12,
            default_settings.create("/fake/state.json").timing,
            function(error_message)
                result = error_message or "shown"
            end
        )
        world.advance(5)
        expect.equal(result, "shown")
        expect.equal(world.displays[2].active_space_id, 12)
        expect.equal(world.focused_display_uuid, DELL_SCREEN.uuid)
        expect.equal(world.mission_control_actions, { "show 12" })
        expect.equal(world.mission_control_openings, 1)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.key_strokes, {})
        expect.equal(world.tasks, {})
    end,

    a_profile_records_a_window_that_hammerspoon_has_not_seen = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(65)
        expect.equal(recorded_sight(controller, 1, reading.id), "in sight")
        local arrangement =
            profile_state.find_arrangement(controller.state, 1, MONITOR_CONFIGURATION_KEY)
        local record = arrangement.windows[#arrangement.windows]
        expect.equal(record.title, "Reading list")
        expect.equal(record.desktop_number, 3)
        expect.equal(record.unit_frame ~= nil, true)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.window_moves, {})
    end,

    a_switch_brings_a_window_not_seen_into_view_and_minimizes_it = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(65)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(world.window_moves, { reading.id .. " to 3" })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.windows[reading.id].is_minimized, true)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(read_busy_messages(world), {
            "Arranging Profile 1… please wait",
            "Arranging Profile 2… please wait",
            "Finding the windows on other desktops… please wait",
            "Arranging Profile 2… please wait",
        })
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

    a_row_warns_when_macos_uses_its_shortcut = function()
        local world, controller = start_world()
        world.symbolic_hotkeys["61"] =
            { enabled = true, value = { parameters = { 32, 49, 1835008 }, type = "standard" } }
        world.symbolic_hotkeys["120"] =
            { enabled = true, value = { parameters = { 65535, 20, 1966080 }, type = "standard" } }
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
        local pending = controller.shortcut_window.model.pending
        expect.equal(pending.text, "Control-Option-Shift-Command-3")
        expect.equal(pending.macos.name, "Switch to Desktop 3")
        world.post_to_webview({ kind = "resolve" })
        expect.equal(controller.shortcuts:find_shortcut("window_search.toggle").key, "3")
        expect.equal(world.hotkey_by_shortcut["ctrl+alt+shift+cmd 3"] ~= nil, true)
        expect.equal(
            find_shortcut_row(controller, "window_search.toggle").macos_conflict.name,
            "Switch to Desktop 3"
        )
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
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.notifications, {})
    end,

    a_switch_keeps_the_desktops_that_the_profile_recorded = function()
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
        expect.equal(world.mission_control_actions, {})
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
            { "unminimize 42", "setFrame 41", "minimize 42", "setFrame 41" }
        )
        expect.equal(world.window_moves, { "41 to 3", "41 to 14", "41 to 3", "41 to 14" })
        expect.equal(world.frames_set_out_of_view, {})
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
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local opened = find_window_titled(world, "Start Page")
        expect.equal(opened ~= nil, true)
        expect.equal(opened.space_id, 14)
        expect.equal(opened.is_minimized, false)
        expect_frame_near(opened.frame, { x = 0, y = 25, w = 720, h = 875 })
        expect.equal(world.menu_selections, { "com.apple.Safari New Window" })
        expect.equal(world.window_moves, { opened.id .. " to 14" })
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.mission_control_openings, 0)
        expect.equal(recorded_sight(controller, 1, opened.id), "in sight")
        expect.equal(world.notifications, {})
    end,

    a_closed_window_is_forgotten_under_the_action_that_forgets = function()
        local world, controller =
            start_world({ unmatched_window_action = unmatched_window_action.FORGET })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(41)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(find_window_titled(world, "Start Page"), nil)
        expect.equal(world.menu_selections, {})
        expect.equal(recorded_sight(controller, 1, 41), nil)
        expect.equal(recorded_sight(controller, 1, 42), "in sight")
        expect.equal(world.notifications, {})
    end,

    an_unknown_action_for_an_unmatched_window_stops_the_start = function()
        local is_started = pcall(start_world, { unmatched_window_action = "drop" })
        expect.equal(is_started, false)
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
            "Arranging Profile 1… please wait",
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
        expect.equal(shown, {
            "Arranging Profile 1… please wait",
            "Monitors changed, waiting for macOS… please wait",
        })
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
        expect.equal(shown, {
            "Arranging Profile 1… please wait",
            "Arranging Profile 2… please wait",
            "Arranging Profile 1… please wait",
        })
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
        expect.equal(world.mission_control_actions, { "show 14", "show 3", "show 14" })
        expect.equal(world.key_strokes, {})
        local shown, visible_count = read_busy_messages(world)
        expect.equal(shown, {
            "Arranging Profile 1… please wait",
            "Showing desktop 2 of built-in… please wait",
            "Showing desktop 1 of built-in… please wait",
            "Showing desktop 2 of built-in… please wait",
        })
        expect.equal(visible_count, 0)
        expect.equal(controller.is_showing_desktop, false)
    end,

    a_press_of_the_list_during_a_switch_is_refused = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.app_hotkeys["2"]()
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        expect.equal(world.notifications, {})
        local shown, visible_count = read_busy_messages(world)
        expect.equal(shown[#shown], "Arranging Profile 1… please wait")
        expect.equal(visible_count, 1)
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(controller.is_busy, false)
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.displays[1].active_space_id, 3)
    end,

    a_switch_during_a_press_of_the_list_is_refused = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.app_hotkeys["2"]()
        expect.equal(controller.is_showing_desktop, true)
        world.hotkeys["2"]()
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(controller.is_showing_desktop, false)
        expect.equal(world.focused_window_id, 41)
    end,

    a_monitor_change_during_a_press_of_the_list_is_restored_after_the_press = function()
        local timing = default_settings.create("/fake/state.json").timing
        timing.screen_settle_seconds = 0.2
        local world, controller = start_world({ timing = timing })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.app_hotkeys["2"]()
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(0.3)
        expect.equal(controller.is_showing_desktop, true)
        expect.equal(controller.is_busy, false)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 14" })
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(read_busy_messages(world), {
            "Arranging Profile 1… please wait",
            "Showing desktop 2 of built-in… please wait",
            "Monitors changed, waiting for macOS… please wait",
            "Arranging Profile 1 for built-in… please wait",
        })
        expect.equal(controller.is_busy, false)
        expect.equal(controller.are_saves_suspended, false)
        expect_frame_near(world.windows[42].frame, { x = 756, y = 25, w = 756, h = 957 })
    end,

    a_desktop_that_mission_control_does_not_show_is_reported = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.ignores_desktop_presses = true
        world.app_hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
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

    the_diagnostics_show_the_build_the_desktops_shown_and_the_numbers_of_the_profile = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(61)
        local printed, original_print = {}, print
        _G.print = function(text) -- luacheck: ignore 122
            table.insert(printed, text)
        end
        local is_printed, error_message =
            pcall(find_menu_item(world, "Print diagnostics to the console").fn)
        _G.print = original_print -- luacheck: ignore 122
        if not is_printed then
            error(error_message, 0)
        end
        local lines = {}
        for line in table.concat(printed, "\n"):gmatch("[^\n]+") do
            lines[line] = true
        end
        expect.equal(lines["Hammerspoon 8cde946"], true)
        expect.equal(lines["  desktops of BUILTIN-UUID (built-in): 1=3 2=14 3=64, shown 1"], true)
        expect.equal(lines["profile 1 holds 3 desktops on built-in and shows desktop 1"], true)
        expect.equal(lines["profile 1 had the focus on built-in"], true)
        expect.equal(lines["windows out of reach: 1"], true)
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

    a_window_on_another_desktop_of_its_screen_moves_back_by_its_id = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.windows[41].space_id = 64
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_moves, { "41 to 14" })
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.notifications, {})
    end,

    a_window_that_does_not_move_is_reported_at_each_switch = function()
        local world = start_world()
        world.unmovable_window_ids[41] = true
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.windows[41].space_id = 64
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_moves, { "41 to 14" })
        expect.equal(world.windows[41].space_id, 64)
        world.hotkeys["1"]()
        world.windows[41].space_id = 14
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_moves, { "41 to 14", "41 to 64" })
        local function describe_failure(desktop_number)
            return string.format(
                'Safari window "Inbox" did not reach desktop %d of built-in: did not reach its'
                    .. " desktop within 1 seconds (1 problems in the Hammerspoon console)",
                desktop_number
            )
        end
        expect.equal(world.notifications, { describe_failure(2), describe_failure(3) })
    end,

    control_option_command_with_the_number_clears_a_profile_after_the_confirmation = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkey_by_shortcut["ctrl+alt+cmd 1"]()
        expect.equal(profile_state.has_arrangements(controller.state, 1), true)
        world.alert_button = "Clear"
        world.hotkey_by_shortcut["ctrl+alt+cmd 1"]()
        expect.equal(profile_state.has_arrangements(controller.state, 1), false)
        expect.equal(
            world.alerts[#world.alerts],
            "Profile 1 is cleared and records the windows from now on"
        )
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

    opening_a_window_for_a_number_shows_a_message = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "4", app = "com.microsoft.Word" }
        )
        world.app_hotkeys["4"]()
        local shown, visible_while_opening = read_busy_messages(world)
        expect.equal(shown[#shown], "Opening a window of Microsoft Word… please wait")
        expect.equal(visible_while_opening, 1)
        expect.equal(controller.is_showing_desktop, true)
        world.advance(SETTLE_SECONDS)
        local _, visible_count = read_busy_messages(world)
        expect.equal(visible_count, 0)
        expect.equal(controller.is_showing_desktop, false)
        expect.equal(world.focused_window_id, find_window_titled(world, "Document1").id)
    end,

    a_number_without_a_window_during_a_switch_keeps_the_message_of_the_switch = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "4", app = "com.microsoft.Word" }
        )
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.app_hotkeys["4"]()
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        expect.equal(world.notifications, {})
        local shown, visible_count = read_busy_messages(world)
        expect.equal(shown[#shown], "Arranging Profile 1… please wait")
        expect.equal(visible_count, 1)
        world.advance(SETTLE_SECONDS)
        expect.equal(find_window_titled(world, "Document1"), nil)
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

    the_search_focuses_the_application_before_the_press_so_that_the_desktop_stays = function()
        local world, notes = start_bounce_world()
        world.advance(SETTLE_SECONDS)
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        world.type_keys("report")
        world.advance(0)
        expect.equal(
            world.read_search_panel().windows,
            { "selection Report.docx | Microsoft Word" }
        )
        world.press_key("return")
        world.advance(SETTLE_SECONDS)
        expect.equal(world.bounces, {})
        expect.equal(world.displays[2].active_space_id, 9)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(list_focus_operations(world), { "focus " .. notes.id, "focus 43" })
        expect.equal(world.focused_window_id, 43)
        expect.equal(world.notifications, {})
    end,

    the_search_focuses_the_application_before_the_press_for_a_window_not_reached = function()
        local world, notes = start_bounce_world()
        local letter = world.create_unseen_window("com.microsoft.Word", "Letter.docx", 10)
        world.advance(SETTLE_SECONDS)
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        world.type_keys("letter")
        world.advance(0)
        expect.equal(
            world.read_search_panel().windows,
            { "selection Letter.docx | Microsoft Word" }
        )
        world.press_key("return")
        world.advance(SETTLE_SECONDS)
        expect.equal(world.bounces, {})
        expect.equal(world.displays[2].active_space_id, 10)
        expect.equal(world.mission_control_openings, 1)
        expect.equal(list_focus_operations(world), { "focus " .. notes.id, "focus " .. letter.id })
        expect.equal(world.notifications, {})
    end,

    a_number_without_a_selected_window_passes_the_recorded_window_for_the_focus = function()
        local world = start_bounce_world()
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
        expect.equal(world.mission_control_actions, { "show 64" })
        expect.equal(world.focused_window_id, reading.id)
        local shown = read_busy_messages(world)
        expect.equal(shown[#shown], "Showing desktop 3 of built-in… please wait")
    end,

    a_press_of_the_search_during_a_switch_is_refused = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        world.click("window:41")
        world.advance(0)
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        expect.equal(world.notifications, {})
        local shown = read_busy_messages(world)
        expect.equal(shown[#shown], "Arranging Profile 1… please wait")
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, {})
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

    a_window_that_its_application_keeps_ordered_out_shows_in_no_list = function()
        local world = start_world()
        local closed = world.create_unseen_window("com.apple.Notes", "New Note", 64)
        world.windows[closed.id].is_ordered_out = true
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(SETTLE_SECONDS)
        world.hotkey_by_shortcut[SEARCH_SHORTCUT]()
        world.advance(1)
        expect.equal(#world.read_search_panel().windows, 3)
        expect.equal(world.read_search_panel().windows[3], "plain Reading list | Safari")
    end,

    the_numbered_list_holds_a_window_on_a_desktop_not_visited = function()
        local world = start_world({ list_layout = list_layout.ROWS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(2 * SETTLE_SECONDS + 1)
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
        expect.equal(world.mission_control_actions, { "show 64" })
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

    a_second_monitor_change_during_a_restore_keeps_the_layout = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        local recorded_frame = find_record_of_profile_1(controller, 42).unit_frame
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(3.1)
        expect.equal(controller.is_busy, true)
        world.screens[1].frame = BUILTIN_FRAME
        world.screen_watchers[1]()
        local is_message_shown_between = false
        for _ = 1, 100 do
            world.advance(0.05)
            if not controller.is_busy and controller.screen_timer then
                expect.equal(controller.are_saves_suspended, true)
                is_message_shown_between = controller.busy_message_text
                    == "Monitors changed, waiting for macOS… please wait"
            end
        end
        world.advance(SETTLE_SECONDS)
        expect.equal(is_message_shown_between, true)
        expect.equal(find_record_of_profile_1(controller, 42).unit_frame, recorded_frame)
        expect_frame_near(world.windows[42].frame, { x = 720, y = 25, w = 720, h = 875 })
        expect.equal(controller.are_saves_suspended, false)
    end,

    a_deactivation_during_a_restore_is_refused_with_an_alert = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(3.1)
        expect.equal(controller.is_busy, true)
        world.hotkeys["0"]()
        expect.equal(world.alerts[#world.alerts], "Desktop Manager is still switching")
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
    end,

    a_window_that_accessibility_does_not_reach_in_view_goes_back_and_is_reported = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.unreachable_window_ids[reading.id] = true
        world.advance(65)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_moves, { reading.id .. " to 3", reading.id .. " to 64" })
        expect.equal(world.windows[reading.id].space_id, 64)
        expect.equal(world.notifications, {
            'Safari window "Reading list" stays on desktop 3,'
                .. " because accessibility did not reach it in view"
                .. " (2 problems in the Hammerspoon console)",
        })
    end,

    a_switch_that_the_watchdog_stopped_removes_no_desktop = function()
        local timing = default_settings.create("/fake/state.json").timing
        timing.busy_watchdog_seconds = 0.5
        local world, controller = start_world({ timing = timing })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14, 64, 98, 99 }
        world.advance(61)
        world.mission_control_actions = {}
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.notifications, {
            "Desktop Manager stopped a switch that did not finish within 0.5 seconds"
                .. " (1 problems in the Hammerspoon console)",
        })
        expect.equal(world.mission_control_actions, {})
        expect.equal(world.displays[1].space_ids, { 3, 14, 64, 98, 99 })
        expect.equal(world.is_mission_control_open, false)
        expect.equal(controller.is_busy, false)
    end,

    the_watchdog_closes_mission_control_after_a_step_that_raised_while_it_showed = function()
        local world, controller = start_world()
        world.displays[1].active_space_id = 14
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.swallows_timer_errors = true
        make_desktops_unreadable_once_mission_control_opens(world)
        world.hotkeys["1"]()
        world.advance(5)
        expect.equal(world.is_mission_control_open, true)
        expect.equal(#world.timer_errors > 0, true)
        world.desktop_read_error = nil
        world.advance(90)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(controller.is_busy, false)
        expect.equal(world.notifications, { WATCHDOG_MESSAGE })
    end,

    the_watchdog_resumes_the_saves_after_a_restore_that_raised = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.swallows_timer_errors = true
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(3.1)
        expect.equal(controller.is_busy, true)
        world.desktop_read_error = "macOS stopped answering"
        world.advance(91)
        world.desktop_read_error = nil
        expect.equal(#world.timer_errors > 0, true)
        expect.equal(controller.is_busy, false)
        expect.equal(controller.are_saves_suspended, false)
        expect.equal(world.notifications, { WATCHDOG_MESSAGE })
        world.windows[42].frame = { x = 100, y = 125, w = 600, h = 500 }
        world.advance(61)
        local unit_frame = find_record_of_profile_1(controller, 42).unit_frame
        expect.equal(math.abs(unit_frame.x - 100 / 1512) < 0.001, true)
    end,

    the_watchdog_ends_a_press_that_never_called_back = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.swallows_timer_errors = true
        make_desktops_unreadable_once_mission_control_opens(world)
        world.app_hotkeys["2"]()
        world.advance(5)
        expect.equal(controller.is_showing_desktop, true)
        world.desktop_read_error = nil
        world.advance(90)
        expect.equal(controller.is_showing_desktop, false)
        expect.equal(world.is_mission_control_open, false)
        expect.equal(world.notifications, { WATCHDOG_MESSAGE })
        local _, visible_count = read_busy_messages(world)
        expect.equal(visible_count, 0)
    end,

    a_save_while_the_monitors_settle_records_nothing = function()
        local world, controller = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.url_handlers["desktop-manager"]("desktop-manager", { action = "save" })
        expect.equal(
            profile_state.find_arrangement(controller.state, 1, MONITOR_CONFIGURATION_KEY),
            nil
        )
        world.advance(SETTLE_SECONDS)
        expect.equal(
            profile_state.find_arrangement(controller.state, 1, MONITOR_CONFIGURATION_KEY) ~= nil,
            true
        )
    end,

    the_list_reaches_a_window_in_full_screen = function()
        local world = start_world()
        world.displays[1].full_screen_space_ids = { 500 }
        world.windows[41].space_id = 500
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "number-app", number = "5", app = "Safari" }
        )
        world.app_hotkeys["5"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 500" })
        expect.equal(world.displays[1].active_space_id, 500)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.notifications, {})
    end,

    a_press_holds_its_message_until_accessibility_reaches_the_window = function()
        local timing = default_settings.create("/fake/state.json").timing
        timing.window_reach_timeout_seconds = 3
        local world, controller = start_world({ list_layout = list_layout.ROWS, timing = timing })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(2 * SETTLE_SECONDS + 1)
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
            if #world.mission_control_actions > 0 and not controller.is_showing_desktop then
                was_released_before_the_focus = true
            end
        end
        expect.equal(world.mission_control_actions, { "show 64" })
        expect.equal(world.focused_window_id, reading.id)
        expect.equal(was_released_before_the_focus, false)
        world.advance(1)
        expect.equal(controller.is_showing_desktop, false)
        local _, visible_count = read_busy_messages(world)
        expect.equal(visible_count, 0)
    end,

    a_window_that_accessibility_does_not_reach_after_a_press_is_reported = function()
        local world = start_world({ list_layout = list_layout.ROWS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local reading = world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.unreachable_window_ids[reading.id] = true
        world.advance(2 * SETTLE_SECONDS + 1)
        world.held_modifiers = { ctrl = true, alt = true }
        world.app_hotkeys["2"]()
        world.app_hotkeys["2"]()
        world.release_modifiers()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 64" })
        expect.equal(world.notifications, {
            'Safari window "Reading list" did not appear within 1 seconds after its desktop'
                .. " showed (1 problems in the Hammerspoon console)",
        })
        expect.equal(world.focused_window_id, nil)
    end,

    a_restore_after_a_change_of_monitors_leaves_a_window_in_full_screen_first = function()
        local world = start_world()
        world.displays[1].full_screen_space_ids = { 500 }
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.displays[1].active_space_id = 500
        world.screens[1].frame = { x = 0, y = 25, w = 1512, h = 957 }
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 3" })
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.frames_set_out_of_view, {})
        expect_frame_near(world.windows[42].frame, { x = 756, y = 25, w = 756, h = 957 })
        expect.equal(world.notifications, {})
    end,

    a_switch_gives_the_focus_to_a_window_when_the_press_leaves_the_focus = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.press_moves_focus = false
        local notes = world.add_window_of("com.microsoft.Word", "Notes.docx", 14)
        world.displays[1].active_space_id = 14
        world.displays[2].active_space_id = 9
        world.focused_display_uuid = BUILTIN_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].active_space_id = 3
        world.displays[2].active_space_id = 7
        world.focused_display_uuid = DELL_SCREEN.uuid
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "show 9", "show 14" })
        expect.equal(world.focused_display_uuid, BUILTIN_SCREEN.uuid)
        expect.equal(world.focused_window_id, notes.id)
    end,

    a_switch_waits_for_the_release_of_the_modifiers_before_mission_control_opens = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14 }
        world.held_modifiers = { cmd = true, alt = true, shift = true }
        world.hotkeys["1"]()
        world.advance(1)
        expect.equal(world.mission_control_openings, 0)
        world.release_modifiers()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_actions, { "add 2000" })
        expect.equal(world.displays[1].space_ids, { 3, 14, 2000 })
        expect.equal(world.notifications, {})
    end,

    a_modifier_held_through_a_switch_keeps_mission_control_closed_and_is_reported = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.displays[1].space_ids = { 3, 14 }
        world.held_modifiers = { cmd = true, alt = true, shift = true }
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.mission_control_openings, 0)
        expect.equal(world.displays[1].space_ids, { 3, 14 })
        expect.equal(#world.notifications, 1)
        expect.equal(world.notifications[1]:match("^Release the modifier keys") ~= nil, true)
    end,

    the_first_record_of_a_configuration_holds_the_desktops_that_macos_moved_there = function()
        local world, controller = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        local arrangement =
            profile_state.find_arrangement(controller.state, 1, MONITOR_CONFIGURATION_KEY)
        expect.equal(arrangement.monitors[1].desktop_count, 5)
        world.connect_screen(DELL_SCREEN, { 20 })
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        world.advance(61)
        world.disconnect_screen(DELL_SCREEN.uuid)
        world.screen_watchers[1]()
        world.advance(SETTLE_SECONDS)
        local space_ids = world.displays[1].space_ids
        expect.equal(#space_ids, 5)
        expect.equal(world.windows[41].space_id, space_ids[4])
        expect.equal(world.windows[43].space_id, space_ids[5])
    end,

    the_busy_message_shows_at_the_level_overlay = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        local levels = {}
        for _, canvas in ipairs(world.canvases) do
            if #canvas.elements == 2 and canvas.elements[2].type == "text" then
                table.insert(levels, canvas.window_level)
            end
        end
        expect.equal(levels, { world.window_levels.overlay })
    end,

    the_check_before_a_removal_walks_every_window_once = function()
        local world, controller = start_world()
        open_app_pool_window(world)
        world.post_to_webview({
            kind = "tick",
            bundle_id = "com.microsoft.Word",
            app_name = "Microsoft Word",
            is_listed = true,
        })
        local first = world.add_window_of("com.microsoft.Word", "First.docx", 64)
        local second = world.add_window_of("com.microsoft.Word", "Second.docx", 64)
        world.applications["com.microsoft.Word"].is_dropped_by_filter_while_hidden = true
        world.applications["com.microsoft.Word"].is_hidden = true
        local calls_before = world.all_windows_calls
        expect.equal(controller:find_window_that_keeps_desktop({ 42, first.id, second.id }), 42)
        expect.equal(world.all_windows_calls - calls_before, 1)
    end,

    the_list_leaves_out_the_windows_of_hidden_applications_by_default = function()
        expect.equal(
            default_settings.create("/fake/state.json").hidden_application_windows,
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
        world.advance(SETTLE_SECONDS)
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
        world.advance(SETTLE_SECONDS)
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.focused_window_id, notes.id)
        expect.equal(world.displays[1].active_space_id, 64)
    end,

    an_unknown_choice_for_hidden_application_windows_stops_the_start = function()
        expect.raises(function()
            start_world({ hidden_application_windows = "show_some" })
        end, 'the setting hidden_application_windows is "show_some", which names no choice')
    end,

    every_window_of_hidden_applications_leaves_out_their_other_elements = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LIST_ALL)
        local sheet = world.add_window_of("com.microsoft.Word", "Save changes?", 3)
        world.windows[sheet.id].role = "AXSheet"
        expect.equal(read_list_after_press(world, "1")[4], " 2   Safari")
        world.press_escape()
        world.release_modifiers()
        world.advance(SETTLE_SECONDS)
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
        local world = start_world({
            hidden_application_windows = hidden_application_windows.LEAVE_OUT,
            list_layout = list_layout.ROWS,
        })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
            world.advance(SETTLE_SECONDS)
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
        local world = start_world({ list_layout = list_layout.ROWS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.applications["com.apple.Safari"].is_running = false
        local calls_before = world.all_windows_calls
        read_list_after_press(world, "1")
        expect.equal(world.all_windows_calls, calls_before)
    end,

    a_press_of_a_hidden_application_under_leave_out_shows_the_desktop_of_its_window = function()
        local world = start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        read_list_after_press(world, "2")
        world.release_modifiers()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.focused_window_id, 41)
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.menu_selections, {})
        local shown, visible_count = read_busy_messages(world)
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
        world.advance(SETTLE_SECONDS)
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
        local shown, visible_while_waiting = read_busy_messages(world)
        expect.equal(shown[#shown], "Showing desktop 3 of built-in… please wait")
        expect.equal(visible_while_waiting, 1)
        expect.equal(controller.is_showing_desktop, true)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, notes.id)
        expect.equal(world.menu_selections, {})
        expect.equal(#world.window_order, window_count)
        local _, visible_count = read_busy_messages(world)
        expect.equal(visible_count, 0)
        expect.equal(controller.is_showing_desktop, false)
    end,

    a_window_on_another_desktop_without_a_standard_subrole_in_time_is_reported = function()
        local world, _, notes =
            start_world_with_hidden_applications(hidden_application_windows.LEAVE_OUT)
        world.close_window(42)
        world.windows[notes.id].is_unseen = true
        world.applications["com.microsoft.Word"].standard_delay_after_unhide_seconds = 5
        read_list_after_press(world, "1")
        world.release_modifiers()
        world.advance(SETTLE_SECONDS)
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.displays[1].active_space_id, 14)
        expect.equal(world.menu_selections, { "com.apple.Safari New Window" })
        expect.equal(world.focused_window_id, find_window_titled(world, "Start Page").id)
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
        local shown, visible_while_waiting = read_busy_messages(world)
        expect.equal(shown[#shown], "Unhiding Microsoft Word… please wait")
        expect.equal(visible_while_waiting, 1)
        expect.equal(controller.is_showing_desktop, true)
        world.advance(0.4)
        expect.equal(world.focused_window_id, 42)
        world.advance(SETTLE_SECONDS)
        expect.equal(world.focused_window_id, 42)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.menu_selections, {})
        expect.equal(#world.window_order, window_count)
        local _, visible_count = read_busy_messages(world)
        expect.equal(visible_count, 0)
        expect.equal(controller.is_showing_desktop, false)
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
        local shown = read_busy_messages(world)
        expect.equal(shown[#shown], "Showing desktop 3 of built-in… please wait")
        world.advance(SETTLE_SECONDS)
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
        local shown = read_busy_messages(world)
        expect.equal(shown[#shown], "Unhiding Microsoft Word… please wait")
        expect.equal(controller.is_showing_desktop, true)
        world.advance(SETTLE_SECONDS)
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
        world.advance(SETTLE_SECONDS)
        expect.equal(
            world.alerts[#world.alerts],
            "Microsoft Word showed no standard window in the 1-second wait"
                .. " after its unhide (1 problems in the Hammerspoon console)"
        )
        expect.equal(world.menu_selections, {})
        expect.equal(#world.window_order, window_count)
    end,

    a_hidden_application_without_any_window_gets_a_new_window = function()
        local world = start_world({
            hidden_application_windows = hidden_application_windows.LEAVE_OUT,
            list_layout = list_layout.ROWS,
        })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(41)
        world.hide_application("com.apple.Safari")
        expect.equal(read_list_after_press(world, "2"), {
            " 1   Microsoft Word",
            " Draft.docx",
            ">2   Safari",
            " hidden, a press unhides it",
        })
        world.release_modifiers()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.menu_selections, { "com.apple.Safari New Window" })
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.focused_window_id, find_window_titled(world, "Start Page").id)
    end,

    the_columns_mark_a_hidden_application_under_leave_out = function()
        local world =
            start_world({ hidden_application_windows = hidden_application_windows.LEAVE_OUT })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
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
            local world = start_world({
                hidden_application_windows = setting,
                list_layout = list_layout.ROWS,
            })
            world.hotkeys["1"]()
            world.advance(SETTLE_SECONDS)
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
        world.advance(SETTLE_SECONDS)
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
            local world = start_world({
                hidden_application_windows = setting,
                list_layout = list_layout.ROWS,
            })
            local missed = world.add_window_of("com.apple.Safari", "Reading List", 3)
            world.windows[missed.id].is_missed_by_filter = true
            world.hotkeys["1"]()
            world.advance(SETTLE_SECONDS)
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

    the_console_names_the_empty_desktops_that_stay_and_the_desktops_removed = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        leave_notes_to_macos(world)
        world.displays[1].space_ids = { 3, 14, 64, 97, 98, 99 }
        world.add_window_of("com.apple.Notes", "Shopping", 98)
        world.advance(61)
        local lines = record_log_lines(world, function()
            world.hotkeys["1"]()
            world.advance(SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            "switching to profile 1: 2 of 2 saved windows open, concealing <inspected>",
            "restoring profile 1: 2 of 2 saved windows open, plan <inspected>",
            "built-in keeps 2 desktops beyond its 3, because they show or hold a window, or lie"
                .. " below one that does, as the empty desktops 97",
            "removing the empty desktops 99 beyond desktop 3 of built-in",
            "0.00 seconds for the release of the modifiers, 0.00 seconds until Mission Control"
                .. " showed",
            "profile 1 is active after 2.3 seconds, with 0 problems",
        })
    end,

    the_console_gives_the_plan_and_the_duration_of_a_switch = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        local lines = record_log_lines(world, function()
            world.hotkeys["1"]()
            world.advance(SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            "switching to profile 1: 2 of 2 saved windows open, concealing <inspected>",
            "restoring profile 1: 2 of 2 saved windows open, plan <inspected>",
            "profile 1 is active after 1.1 seconds, with 0 problems",
        })
    end,

    the_console_names_the_window_that_the_profile_forgets = function()
        local world = start_world({ unmatched_window_action = unmatched_window_action.FORGET })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(41)
        local lines = record_log_lines(world, function()
            world.hotkeys["1"]()
            world.advance(SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            "switching to profile 1: 1 of 2 saved windows open, concealing <inspected>",
            'profile 1: Safari window "Inbox" is gone, and the profile forgets it',
            "restoring profile 1: 1 of 2 saved windows open, plan <inspected>",
            "profile 1 is active after 1.1 seconds, with 0 problems",
        })
    end,

    the_console_names_the_gone_and_unseen_records_in_their_order = function()
        local world = start_world()
        world.add_window_of("com.apple.Safari", "Reading List", 3)
        local notes = world.add_window_of("com.microsoft.Word", "Notes.docx", 3)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.minimize_window(41)
        world.minimize_window(notes.id)
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(41)
        world.close_window(notes.id)
        world.windows[42].is_minimized = false
        world.windows[42].space_id = 64
        world.windows[42].is_unseen = true
        world.windows[42].is_ordered_out = true
        local lines = record_log_lines(world, function()
            world.hotkeys["1"]()
            world.advance(SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            "switching to profile 1: 1 of 4 saved windows open, concealing <inspected>",
            'Safari window "Inbox" is recorded out of sight and gone',
            'Microsoft Word window "Draft.docx" stays on desktop 64, where Hammerspoon has not'
                .. " seen it",
            'Microsoft Word window "Notes.docx" is recorded out of sight and gone',
            "restoring profile 1: 1 of 4 saved windows open, plan <inspected>",
            "profile 1 is active after 1.1 seconds, with 0 problems",
        })
    end,

    the_console_names_a_reopened_window_with_its_new_id = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.close_window(42)
        local lines = record_log_lines(world, function()
            world.create_window("com.microsoft.Word", "Draft.docx")
            world.advance(SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            'Microsoft Word window "Draft.docx" was reopened as window 1001, which was 42',
        })
    end,

    the_console_counts_the_windows_that_a_switch_moves_into_view = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(61)
        local lines = record_log_lines(world, function()
            world.hotkeys["2"]()
            world.advance(SETTLE_SECONDS)
        end)
        expect.equal(lines, {
            "moving 1 windows into view to reach them",
            "switching to profile 2: 0 of 0 saved windows open, concealing <inspected>",
            "profile 2 is active after 0.1 seconds, with 0 problems",
        })
    end,

    the_console_says_why_a_slow_snapshot_stops_the_snapshots = function()
        local world = start_world({ preview_method = preview_method.BLURRED_SNAPSHOTS })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.snapshot_seconds = 2
        local lines = record_log_lines(world, function()
            world.held_modifiers = { ctrl = true, alt = true }
            world.app_hotkeys["1"]()
            world.advance(1)
        end)
        expect.equal(lines, {
            "a snapshot took 2.0 seconds, so the list shows icons until the next reload",
        })
    end,

    the_diagnostics_print_every_screen_desktop_number_and_window_of_two_screens = function()
        local world = start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(61)
        local printed, original_print = {}, print
        _G.print = function(text) -- luacheck: ignore 122
            table.insert(printed, text)
        end
        local is_printed, error_message =
            pcall(find_menu_item(world, "Print diagnostics to the console").fn)
        _G.print = original_print -- luacheck: ignore 122
        if not is_printed then
            error(error_message, 0)
        end
        local lines = {}
        for line in table.concat(printed, "\n"):gmatch("[^\n]+") do
            table.insert(lines, line)
        end
        expect.equal(lines[3]:match("^running timers: %d+$") ~= nil, true)
        lines[3] = "running timers"
        expect.equal(lines, {
            "Hammerspoon 8cde946",
            "accessibility permission: true",
            "running timers",
            "monitor matching: by_count",
            "application pool: every application except none",
            "monitor configuration: built-in + 1 external",
            '  screen BUILTIN-UUID "Built-in Retina Display" built-in=true slot=built-in',
            '  screen DELL-UUID "DELL S2725DS" built-in=false slot=external 1',
            "  desktops of BUILTIN-UUID (built-in): 1=3 2=14 3=64, shown 1",
            "  desktops of DELL-UUID (external 1): 1=7 2=8 3=9 4=10, shown 1",
            "focused desktop: 3",
            "desktops kept per display: built-in 3, external 1 4",
            "active profile: 1",
            "profile 1 holds 3 desktops on built-in and shows desktop 1",
            "profile 1 holds 4 desktops on external 1 and shows desktop 1",
            "profile 1 had the focus on built-in",
            "application numbers of Profile 1:",
            "  app number 1: Microsoft Word com.microsoft.Word",
            "  app number 2: Safari com.apple.Safari",
            "windows out of reach: 1",
            '  window 41 com.apple.Safari "Inbox" desktop=8 out-of-sight=false in-filter=true'
                .. " recorded=1 in sight",
            '  window 42 com.microsoft.Word "Draft.docx" desktop=3 out-of-sight=false'
                .. " in-filter=true recorded=1 in sight",
            '  window 43 com.microsoft.Word "Report.docx" desktop=9 out-of-sight=false'
                .. " in-filter=true recorded=1 in sight",
        })
    end,
}
