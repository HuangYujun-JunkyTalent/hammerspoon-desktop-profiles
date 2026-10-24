local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local fake_worlds = require("tests.fake_worlds")
local shortcut_center = require("keyboard_shortcuts.macos.shortcut_center")
local shortcut_window = require("keyboard_shortcuts.macos.shortcut_window")

local SEARCH_SHORTCUT = "ctrl+alt+cmd space"
local PROFILE_MODIFIERS = { "cmd", "alt", "shift" }

---Three actions of the desktop manager with their default shortcuts, which do nothing when pressed.
---@type RegisteredAction[]
local ACTIONS = {
    {
        id = "profiles.toggle.2",
        group = "Profiles",
        title = "Activate profile 2, or deactivate it while it is active",
        default = { modifiers = PROFILE_MODIFIERS, key = "2" },
        on_press = function() end,
    },
    {
        id = "profiles.deactivate",
        group = "Profiles",
        title = "Deactivate the active profile",
        default = { modifiers = PROFILE_MODIFIERS, key = "0" },
        on_press = function() end,
    },
    {
        id = "window_search.toggle",
        group = "Window search",
        title = "Show the search of the windows, or close it",
        default = { modifiers = { "ctrl", "alt", "cmd" }, key = "space" },
        on_press = function() end,
    },
}

---The center of the shortcuts and the window of the shortcuts that a case opens.
---@class ShortcutWindowSession
---@field center ShortcutCenter
---@field window ShortcutWindow|nil nil once the window has closed

---@return table world a world with the built-in display alone, and no application
local function start_world()
    return fake_hammerspoon.install({
        screens = { fake_worlds.build_builtin_screen() },
        displays = { { uuid = "BUILTIN-UUID", space_ids = { 3 }, active_space_id = 3 } },
        applications = {},
        windows = {},
    })
end

---Opens the window of the shortcuts of the session, as the menu item "Keyboard shortcuts…" of the
---desktop manager does while no such window shows.
---@param session ShortcutWindowSession
local function open_window(session)
    session.window = shortcut_window.open(session.center, function()
        session.window = nil
    end)
end

---Builds a center of the shortcuts with the three actions and opens its window.
---@param file_path string|nil the file of the overrides, or nil to keep them in memory
---@return ShortcutWindowSession
local function open_shortcut_window(file_path)
    local center = shortcut_center.new(file_path)
    center:register(ACTIONS)
    local session = { center = center }
    open_window(session)
    return session
end

---@param window ShortcutWindow
---@param id string
---@return table the row of the action in the window of the shortcuts
local function find_shortcut_row(window, id)
    for _, group in ipairs(window.model.groups) do
        for _, row in ipairs(group.rows) do
            if row.id == id then
                return row
            end
        end
    end
    error("the window of the shortcuts has no row " .. id)
end

return {
    a_shortcut_of_another_action_moves_after_a_choice = function()
        local world = start_world()
        local session = open_shortcut_window()
        world.post_to_webview("shortcuts", { kind = "record_start" })
        world.post_to_webview("shortcuts", {
            kind = "record",
            id = "profiles.deactivate",
            modifiers = { "cmd", "alt", "shift" },
            key = "2",
        })
        local pending = session.window.model.pending
        expect.equal(pending.holder.id, "profiles.toggle.2")
        expect.equal(pending.text, "Option-Shift-Command-2")
        expect.present(world.hotkey_by_shortcut["cmd+alt+shift 0"], "the hotkey cmd+alt+shift 0")
        world.post_to_webview("shortcuts", { kind = "resolve", remove_holder = true })
        expect.equal(session.window.model.pending, nil)
        expect.equal(world.hotkey_by_shortcut["cmd+alt+shift 0"], nil)
        expect.equal(session.center:find_shortcut("profiles.toggle.2"), nil)
        expect.equal(session.center:find_shortcut("profiles.deactivate").key, "2")
        world.post_to_webview("shortcuts", { kind = "done" })
        expect.equal(session.window, nil)
    end,

    a_shortcut_that_macos_uses_can_turn_the_macos_shortcut_off = function()
        local world = start_world()
        world.symbolic_hotkeys["64"] =
            { enabled = true, value = { parameters = { 32, 49, 1048576 }, type = "standard" } }
        local session = open_shortcut_window()
        world.post_to_webview("shortcuts", { kind = "record_start" })
        world.post_to_webview("shortcuts", {
            kind = "record",
            id = "window_search.toggle",
            modifiers = { "cmd" },
            key = "space",
        })
        expect.equal(session.window.model.pending.macos.name, "Show Spotlight search")
        world.post_to_webview("shortcuts", { kind = "resolve", turn_off_macos = true })
        expect.present(
            world.tasks[#world.tasks].arguments[1]:match("disable_macos_shortcut%.sh$"),
            "disable_macos_shortcut.sh as the script of the last task"
        )
        expect.equal(world.symbolic_hotkeys["64"].enabled, false)
        expect.present(world.hotkey_by_shortcut["cmd space"], "the hotkey cmd space")
        expect.equal(find_shortcut_row(session.window, "window_search.toggle").macos_conflict, nil)
    end,

    a_row_warns_when_macos_uses_its_shortcut = function()
        local world = start_world()
        world.symbolic_hotkeys["61"] =
            { enabled = true, value = { parameters = { 32, 49, 1835008 }, type = "standard" } }
        world.symbolic_hotkeys["120"] =
            { enabled = true, value = { parameters = { 65535, 20, 1966080 }, type = "standard" } }
        local session = open_shortcut_window()
        expect.equal(
            find_shortcut_row(session.window, "window_search.toggle").macos_conflict.name,
            "Select next source in Input menu"
        )
        world.post_to_webview("shortcuts", { kind = "record_start" })
        world.post_to_webview("shortcuts", {
            kind = "record",
            id = "window_search.toggle",
            modifiers = { "ctrl", "alt", "shift", "cmd" },
            key = "3",
        })
        local pending = session.window.model.pending
        expect.equal(pending.text, "Control-Option-Shift-Command-3")
        expect.equal(pending.macos.name, "Switch to Desktop 3")
        world.post_to_webview("shortcuts", { kind = "resolve" })
        expect.equal(session.center:find_shortcut("window_search.toggle").key, "3")
        expect.present(
            world.hotkey_by_shortcut["ctrl+alt+shift+cmd 3"],
            "the hotkey ctrl+alt+shift+cmd 3"
        )
        expect.equal(
            find_shortcut_row(session.window, "window_search.toggle").macos_conflict.name,
            "Switch to Desktop 3"
        )
    end,

    each_drawing_of_the_window_of_the_shortcuts_reads_the_macos_shortcuts_once = function()
        local world = start_world()
        world.execute_calls = 0
        open_shortcut_window()
        expect.equal(world.execute_calls, 1)
        world.post_to_webview("shortcuts", { kind = "remove", id = "window_search.toggle" })
        expect.equal(world.execute_calls, 2)
    end,

    escape_ends_the_recording_of_a_shortcut_and_turns_the_shortcuts_on_again = function()
        local world = start_world()
        local session = open_shortcut_window()
        world.post_to_webview("shortcuts", { kind = "record_start" })
        local hotkey = session.center.binding_by_id["window_search.toggle"].hotkey
        expect.equal(hotkey.is_enabled, false)
        world.post_to_webview("shortcuts", { kind = "record_cancel" })
        expect.equal(hotkey.is_enabled, true)
        expect.equal(find_shortcut_row(session.window, "window_search.toggle").is_default, true)
        expect.equal(session.window.model.problems, {})
    end,

    a_recorded_key_without_a_name_in_hammerspoon_is_reported_above_the_list = function()
        local world = start_world()
        local session = open_shortcut_window()
        world.post_to_webview("shortcuts", { kind = "record_start" })
        world.post_to_webview("shortcuts", { kind = "record_unknown", code = "IntlRo" })
        expect.equal(
            session.window.model.problems,
            { "The key IntlRo has no name in Hammerspoon." }
        )
        expect.equal(session.center.binding_by_id["window_search.toggle"].hotkey.is_enabled, true)
        expect.equal(find_shortcut_row(session.window, "window_search.toggle").is_default, true)
    end,

    delete_leaves_an_action_without_a_shortcut = function()
        local world = start_world()
        local session = open_shortcut_window()
        world.post_to_webview("shortcuts", { kind = "remove", id = "window_search.toggle" })
        expect.equal(world.hotkey_by_shortcut[SEARCH_SHORTCUT], nil)
        local row = find_shortcut_row(session.window, "window_search.toggle")
        expect.equal(row.shortcut, nil)
        expect.equal(row.is_default, false)
        expect.equal(session.center.overrides["window_search.toggle"], false)
    end,

    restore_all_defaults_gives_every_action_its_default_shortcut_again = function()
        local world = start_world()
        local session = open_shortcut_window()
        world.post_to_webview("shortcuts", { kind = "remove", id = "window_search.toggle" })
        world.post_to_webview("shortcuts", { kind = "remove", id = "profiles.deactivate" })
        expect.equal(world.hotkey_by_shortcut["cmd+alt+shift 0"], nil)
        world.post_to_webview("shortcuts", { kind = "reset_all" })
        expect.present(world.hotkey_by_shortcut[SEARCH_SHORTCUT], "the hotkey of the search")
        expect.present(world.hotkey_by_shortcut["cmd+alt+shift 0"], "the hotkey cmd+alt+shift 0")
        expect.equal(find_shortcut_row(session.window, "window_search.toggle").is_default, true)
        expect.equal(find_shortcut_row(session.window, "profiles.deactivate").is_default, true)
        expect.equal(session.center.overrides, {})
        expect.equal(session.window.model.problems, {})
    end,

    the_button_under_a_warning_turns_the_macos_shortcut_off = function()
        local world = start_world()
        world.symbolic_hotkeys["61"] =
            { enabled = true, value = { parameters = { 32, 49, 1835008 }, type = "standard" } }
        local session = open_shortcut_window()
        world.post_to_webview("shortcuts", { kind = "turn_off_macos", id = "window_search.toggle" })
        expect.equal(world.tasks[#world.tasks].arguments[2], "61")
        expect.equal(world.symbolic_hotkeys["61"].enabled, false)
        expect.equal(find_shortcut_row(session.window, "window_search.toggle").macos_conflict, nil)
        expect.equal(session.window.model.problems, {})
    end,

    a_macos_shortcut_that_cannot_be_turned_off_drops_the_choice_and_keeps_the_shortcut = function()
        local world = start_world()
        world.symbolic_hotkeys["64"] =
            { enabled = true, value = { parameters = { 32, 49, 1048576 }, type = "standard" } }
        world.task_exit_code = 1
        local session = open_shortcut_window()
        world.post_to_webview("shortcuts", { kind = "record_start" })
        world.post_to_webview("shortcuts", {
            kind = "record",
            id = "window_search.toggle",
            modifiers = { "cmd" },
            key = "space",
        })
        world.post_to_webview("shortcuts", { kind = "resolve", turn_off_macos = true })
        expect.equal(session.window.model.pending, nil)
        expect.equal(session.window.model.problems, {
            'The macOS shortcut "Show Spotlight search" could not be turned off: ',
        })
        expect.equal(world.symbolic_hotkeys["64"].enabled, true)
        expect.present(world.hotkey_by_shortcut[SEARCH_SHORTCUT], "the hotkey of the search")
        expect.equal(world.hotkey_by_shortcut["cmd space"], nil)
    end,

    a_file_of_shortcuts_that_cannot_be_written_is_reported_and_keeps_the_hotkeys = function()
        local world = start_world()
        world.unwritable_paths[world.shortcuts_file_path] = true
        local session = open_shortcut_window(world.shortcuts_file_path)
        local problems = { "the shortcuts could not be written to /fake/keyboard-shortcuts.json" }
        world.post_to_webview("shortcuts", { kind = "remove", id = "window_search.toggle" })
        expect.equal(session.window.model.problems, problems)
        expect.present(world.hotkey_by_shortcut[SEARCH_SHORTCUT], "the hotkey of the search")
        world.post_to_webview("shortcuts", { kind = "reset_all" })
        expect.equal(session.window.model.problems, problems)
        expect.present(world.hotkey_by_shortcut[SEARCH_SHORTCUT], "the hotkey of the search")
        expect.equal(world.json_files[world.shortcuts_file_path], nil)
    end,

    a_removal_that_cannot_be_written_is_undone_and_stays_undone_at_the_next_change = function()
        local world = start_world()
        local path = world.shortcuts_file_path
        world.unwritable_paths[path] = true
        local session = open_shortcut_window(path)
        world.post_to_webview("shortcuts", { kind = "remove", id = "window_search.toggle" })
        expect.equal(find_shortcut_row(session.window, "window_search.toggle").is_default, true)
        world.unwritable_paths[path] = nil
        world.post_to_webview("shortcuts", { kind = "remove", id = "profiles.deactivate" })
        expect.equal(world.json_files[path], { ["profiles.deactivate"] = false })
        expect.present(world.hotkey_by_shortcut[SEARCH_SHORTCUT], "the hotkey of the search")
        expect.equal(world.hotkey_by_shortcut["cmd+alt+shift 0"], nil)
    end,

    a_reset_that_cannot_be_written_keeps_the_overrides_and_their_hotkeys = function()
        local world = start_world()
        local path = world.shortcuts_file_path
        local session = open_shortcut_window(path)
        world.post_to_webview("shortcuts", { kind = "remove", id = "profiles.deactivate" })
        world.unwritable_paths[path] = true
        world.post_to_webview("shortcuts", { kind = "reset_all" })
        expect.equal(find_shortcut_row(session.window, "profiles.deactivate").is_default, false)
        world.unwritable_paths[path] = nil
        world.post_to_webview("shortcuts", { kind = "remove", id = "window_search.toggle" })
        expect.equal(
            world.json_files[path],
            { ["profiles.deactivate"] = false, ["window_search.toggle"] = false }
        )
        expect.equal(world.hotkey_by_shortcut["cmd+alt+shift 0"], nil)
    end,

    the_window_of_the_shortcuts_runs_its_closing_action_once = function()
        local world = start_world()
        local session = open_shortcut_window()
        local view = session.window.web_window.view
        world.hotkey_events = {}
        world.post_to_webview("shortcuts", { kind = "done" })
        local event_count = #world.hotkey_events
        expect.equal(event_count > 0, true)
        expect.equal(session.window, nil)
        view.window_callback("closing")
        expect.equal(#world.hotkey_events, event_count)
        open_window(session)
        session.window.web_window.view.window_callback("closing")
        expect.equal(session.window, nil)
    end,
}
