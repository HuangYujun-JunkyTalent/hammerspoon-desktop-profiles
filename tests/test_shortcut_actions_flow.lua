local controller_world = require("tests.controller_world")
local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local fake_worlds = require("tests.fake_worlds")
local profile_controller = require("desktop_manager.macos.profile_controller")
local shortcut_center = require("keyboard_shortcuts.macos.shortcut_center")
local tiling_controller = require("window_tiling.macos.tiling_controller")
local tiling_settings = require("window_tiling.default_settings")

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

return {
    a_shortcut_from_the_file_replaces_the_default = function()
        local world = fake_hammerspoon.install({
            screens = { controller_world.BUILTIN_SCREEN },
            displays = {
                {
                    uuid = controller_world.BUILTIN_SCREEN.uuid,
                    space_ids = { 3 },
                    active_space_id = 3,
                },
            },
            applications = {},
            windows = {},
        })
        world.json_files[world.shortcuts_file_path] = {
            ["profiles.toggle.1"] = { modifiers = { "cmd", "alt", "shift" }, key = "a" },
            ["tiling.fill"] = false,
        }
        local shortcuts = shortcut_center.new(world.shortcuts_file_path)
        local controller =
            profile_controller.start(fake_worlds.create_default_settings(), shortcuts)
        tiling_controller.start(tiling_settings.create(), shortcuts)
        shortcuts:check_overrides()
        expect.equal(world.notifications, {})
        shortcuts.overrides["tiling.nowhere"] = false
        shortcuts:check_overrides()
        expect.equal(world.notifications, {
            '/fake/keyboard-shortcuts.json names the action "tiling.nowhere", which no tool has',
        })
        shortcuts.overrides["tiling.nowhere"] = nil
        world.notifications = {}
        expect.equal(world.hotkey_by_shortcut["cmd+alt+shift 1"], nil)
        expect.equal(world.hotkey_by_shortcut["ctrl+alt return"], nil)
        expect.present(world.hotkey_by_shortcut["ctrl+alt left"], "the hotkey ctrl+alt left")
        world.hotkey_by_shortcut["cmd+alt+shift a"]()
        world.advance(controller_world.SETTLE_SECONDS)
        expect.equal(controller.state.active_profile_number, 1)
        expect.equal(world.notifications, {})
    end,

    the_window_of_the_shortcuts_records_a_new_shortcut = function()
        local world, controller = controller_world.start_world()
        controller_world.find_menu_item(world, "Keyboard shortcuts…").fn()
        local row = find_shortcut_row(controller, "window_search.toggle")
        expect.equal(row.title, "Show the search of the windows, or close it")
        expect.equal(
            find_shortcut_row(controller, "profiles.toggle.1").title,
            "Activate profile 1, restore it while it is paused, or deactivate it while it is active"
        )
        expect.equal(row.macos_conflict, nil)
        world.hotkey_events = {}
        world.post_to_webview("shortcuts", { kind = "record_start" })
        expect.present(
            world.hotkey_events[1]:match("^disable"),
            "a disable as the first hotkey event"
        )
        world.post_to_webview("shortcuts", {
            kind = "record",
            id = "window_search.toggle",
            modifiers = { "ctrl", "alt" },
            key = "f",
        })
        expect.equal(controller.shortcut_window.model.pending, nil)
        expect.equal(world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT], nil)
        world.hotkey_by_shortcut["ctrl+alt f"]()
        expect.present(world.read_search_panel(), "the search panel")
        expect.equal(find_shortcut_row(controller, "window_search.toggle").is_default, false)
        world.post_to_webview("shortcuts", { kind = "default", id = "window_search.toggle" })
        expect.equal(world.hotkey_by_shortcut["ctrl+alt f"], nil)
        expect.present(
            world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT],
            "the hotkey of the search"
        )
    end,
}
