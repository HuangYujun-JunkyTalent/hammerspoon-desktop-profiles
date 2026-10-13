local expect = require("tests.expect")
local macos_shortcuts = require("keyboard_shortcuts.core.macos_shortcuts")

---@return table the shortcuts of macOS as `defaults export` gives them on macOS 27.0.1
local function build_symbolic_hotkeys()
    return {
        ["32"] = { enabled = true, value = { parameters = { 65535, 126, 8650752 } } },
        ["60"] = { enabled = true, value = { parameters = { 32, 49, 262144 } } },
        ["64"] = { enabled = false, value = { parameters = { 32, 49, 1048576 } } },
        ["163"] = { enabled = true, value = { parameters = { 65535, 65535, 0 } } },
        ["15"] = { enabled = false },
    }
end

return {
    the_shortcuts_with_a_key_are_listed_with_the_defaults_that_the_file_leaves_out = function()
        local shortcuts = macos_shortcuts.list(build_symbolic_hotkeys())
        local ids = {}
        for _, shortcut in ipairs(shortcuts) do
            table.insert(ids, shortcut.id)
        end
        expect.equal(ids, { 7, 8, 9, 10, 11, 27, 28, 29, 30, 31, 32, 57, 60, 64, 98, 184 })
        expect.equal(shortcuts[11].name, "Mission Control")
        expect.equal(shortcuts[14].is_enabled, false)
    end,

    a_shortcut_of_the_tools_collides_with_an_enabled_shortcut_of_macos = function()
        local shortcuts = macos_shortcuts.list(build_symbolic_hotkeys())
        expect.equal(macos_shortcuts.find_conflict(shortcuts, { "ctrl" }, 49).id, 60)
        expect.equal(macos_shortcuts.find_conflict(shortcuts, { "cmd" }, 49), nil)
        expect.equal(macos_shortcuts.find_conflict(shortcuts, { "ctrl", "alt" }, 49), nil)
        expect.equal(macos_shortcuts.find_conflict(shortcuts, { "shift", "cmd" }, 20).id, 28)
    end,

    an_arrow_matches_without_the_flag_of_the_fn_key = function()
        local shortcuts = macos_shortcuts.list(build_symbolic_hotkeys())
        expect.equal(macos_shortcuts.find_conflict(shortcuts, { "ctrl" }, 126).id, 32)
        expect.equal(macos_shortcuts.find_conflict(shortcuts, { "ctrl", "fn" }, 126).id, 32)
        expect.equal(macos_shortcuts.find_conflict(shortcuts, { "ctrl" }, nil), nil)
        expect.equal(macos_shortcuts.name_of(300), "the macOS shortcut number 300")
    end,
}
