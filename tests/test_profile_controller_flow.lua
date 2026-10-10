local concealment_method = require("desktop_manager.core.concealment_method")
local default_settings = require("desktop_manager.default_settings")
local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local profile_controller = require("desktop_manager.macos.profile_controller")
local profile_state = require("desktop_manager.core.profile_state")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }
local SETTLE_SECONDS = 30

---@param method string|nil a value of concealment_method, or nil for the default
---@return table world
---@return ProfileController controller
local function start_world(method)
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
            { bundle_id = "com.apple.Safari", name = "Safari", is_running = true },
            { bundle_id = "com.microsoft.Word", name = "Microsoft Word", is_running = true },
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
    settings.concealment_method = method or settings.concealment_method
    local controller = profile_controller.start(settings)
    return world, controller
end

return {
    the_first_profile_adopts_the_open_windows = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(profile_state.profile_or_default(controller.state, 1).window_ids, { 41, 42 })
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
        expect.equal(profile_state.holders_by_window_id(controller.state)[news.id], { 2 })
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

    windows_unminimized_onto_the_shown_desktop_are_brought_back_on_visits = function()
        local world = start_world()
        world.does_unminimize_onto_active_desktop = true
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[42].is_minimized, false)
        expect.equal(world.windows[42].space_id, 3)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.key_strokes, { "ctrl+2", "ctrl+1" })
        expect.equal(world.notifications, {})
    end,

    the_hiding_setting_hides_an_application_of_the_old_profile = function()
        local world, controller = start_world(concealment_method.HIDE_APPLICATIONS)
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
        local world, controller = start_world(concealment_method.HIDE_APPLICATIONS)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(SETTLE_SECONDS)
        expect.equal(profile_state.holders_by_window_id(controller.state)[news.id], { 2 })
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

    a_window_brought_back_by_hand_joins_the_profile_and_stays_through_switches = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.unminimize_window(41)
        world.windows[41].frame = { x = 100, y = 100, w = 600, h = 500 }
        world.advance(SETTLE_SECONDS)
        expect.equal(profile_state.holders_by_window_id(controller.state)[41], { 1, 2 })
        world.window_operations = {}
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.window_operations, { "unminimize 42", "minimize 42" })
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.windows[41].frame, { x = 100, y = 100, w = 600, h = 500 })
    end,

    a_window_minimized_by_hand_leaves_a_profile_that_shares_it = function()
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
        world.minimize_window(42)
        world.advance(SETTLE_SECONDS)
        local holders = profile_state.holders_by_window_id(controller.state)
        expect.equal(holders[41], { 2 })
        expect.equal(holders[42], { 1 })
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[42].is_minimized, true)
    end,

    a_window_that_the_filter_drops_while_hidden_comes_back = function()
        local world = start_world(concealment_method.HIDE_APPLICATIONS)
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

    an_unhide_by_the_user_leaves_the_windows_in_sight_and_adds_them_to_the_profile = function()
        local world, controller = start_world(concealment_method.HIDE_APPLICATIONS)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.unhide_application("com.apple.Safari")
        world.advance(SETTLE_SECONDS)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, false)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(profile_state.holders_by_window_id(controller.state)[41], { 1, 2 })
    end,

    a_window_that_no_longer_exists_is_reported = function()
        local world = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        world.windows[41] = nil
        for index, window_id in ipairs(world.window_order) do
            if window_id == 41 then
                table.remove(world.window_order, index)
            end
        end
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(world.notifications, {
            'Safari window "Inbox" of profile 1 was not found'
                .. " (1 problems in the Hammerspoon console)",
        })
    end,

    an_application_that_stays_hidden_is_reported = function()
        local world = start_world(concealment_method.HIDE_APPLICATIONS)
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
        expect.equal(profile_state.holders_by_window_id(controller.state)[relaunched.id], { 1 })
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

    a_bad_url_is_reported = function()
        local world = start_world()
        world.url_handlers["desktop-manager"](
            "desktop-manager",
            { action = "activate", profile = "11" }
        )
        expect.equal(world.notifications, { 'the profile "11" is not a number from 1 to 9' })
    end,
}
