local default_settings = require("desktop_manager.default_settings")
local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local profile_controller = require("desktop_manager.macos.profile_controller")
local profile_state = require("desktop_manager.core.profile_state")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }
local SETTLE_SECONDS = 30

---@return table world
---@return ProfileController controller
local function start_world()
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
    local controller = profile_controller.start(default_settings.create("/fake/state.json"))
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

    a_new_profile_conceals_the_windows_of_the_old_one = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 2)
        expect.equal(world.applications["com.apple.Safari"].is_hidden, true)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, true)
        local arrangement = profile_state.find_arrangement(controller.state, 1, "built-in")
        expect.equal(arrangement.windows[1].desktop_number, 2)
        expect.equal(arrangement.windows[2].desktop_number, 1)
    end,

    a_window_of_a_shared_application_is_minimized_on_the_switch = function()
        local world, controller = start_world()
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        world.hotkeys["2"]()
        world.advance(SETTLE_SECONDS)
        local news = world.create_window("com.apple.Safari", "News")
        world.advance(SETTLE_SECONDS)
        expect.equal(profile_state.owner_by_window_id(controller.state)[news.id], 2)
        expect.equal(world.windows[41].is_minimized, true)
        world.hotkeys["1"]()
        world.advance(SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.windows[news.id].is_minimized, true)
        expect.equal(world.windows[41].is_minimized, false)
        expect.equal(world.windows[41].space_id, 14)
        expect.equal(world.applications["com.microsoft.Word"].is_hidden, false)
        expect.equal(world.displays[1].active_space_id, 3)
        expect.equal(world.key_strokes, { "ctrl+2", "ctrl+1" })
        expect.equal(world.notifications, {})
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
        expect.equal(profile_state.owner_by_window_id(controller.state)[relaunched.id], 1)
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
