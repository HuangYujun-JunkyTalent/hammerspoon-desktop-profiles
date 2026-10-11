local concealment_method = require("desktop_manager.core.concealment_method")
local default_settings = require("desktop_manager.default_settings")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local profile_controller = require("desktop_manager.macos.profile_controller")
local profile_state = require("desktop_manager.core.profile_state")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }
local SETTLE_SECONDS = 30
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

return {
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
        expect.equal(world.key_strokes, { "ctrl+2", "ctrl+1" })
        expect.equal(recorded_sight(controller, 1, opened.id), "in sight")
        expect.equal(world.notifications, {})
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
        world.advance(SETTLE_SECONDS)
        expect.equal(world.alerts, { "Profile 1", "Restoring built-in" })
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
        expect.equal(world.key_strokes, { "ctrl+2", "ctrl+1", "ctrl+2" })
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
        expect.equal(world.key_strokes, { "cmd+7", "cmd+7" })
        expect.equal(world.hotkey_events, {
            "disable cmd 7",
            "enable cmd 7",
            "disable cmd 7",
            "enable cmd 7",
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
}
