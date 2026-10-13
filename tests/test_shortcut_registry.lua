local expect = require("tests.expect")
local shortcut_registry = require("keyboard_shortcuts.core.shortcut_registry")

---@return ShortcutRegistry
local function build_registry()
    local registry = shortcut_registry.new()
    shortcut_registry.add(registry, {
        id = "profiles.toggle.1",
        group = "Profiles",
        title = "Activate profile 1",
        default = { modifiers = { "cmd", "alt", "shift" }, key = "1" },
    })
    shortcut_registry.add(registry, {
        id = "window_search.toggle",
        group = "Window search",
        title = "Show the search",
        default = { modifiers = { "ctrl", "alt", "cmd" }, key = "space" },
    })
    shortcut_registry.add(registry, {
        id = "tiling.fill",
        group = "Window tiling",
        title = "Fill the screen",
        default = { modifiers = { "ctrl", "alt" }, key = "return" },
    })
    return registry
end

local function is_known_key(key)
    return key ~= "nokey"
end

return {
    every_action_takes_its_default_without_overrides = function()
        local resolution = shortcut_registry.resolve(build_registry(), {}, is_known_key)
        expect.equal(resolution.problems, {})
        expect.equal(resolution.shortcut_by_id["tiling.fill"].key, "return")
    end,

    an_override_changes_or_removes_a_shortcut = function()
        local resolution = shortcut_registry.resolve(build_registry(), {
            ["profiles.toggle.1"] = { modifiers = { "ctrl", "shift" }, key = "a" },
            ["tiling.fill"] = false,
        }, is_known_key)
        expect.equal(resolution.problems, {})
        expect.equal(
            resolution.shortcut_by_id["profiles.toggle.1"],
            { modifiers = { "ctrl", "shift" }, key = "a" }
        )
        expect.equal(resolution.shortcut_by_id["tiling.fill"], nil)
    end,

    an_invalid_override_keeps_the_default = function()
        local resolution = shortcut_registry.resolve(build_registry(), {
            ["profiles.toggle.1"] = { modifiers = { "hyper" }, key = "a" },
            ["tiling.fill"] = { modifiers = { "ctrl" }, key = "nokey" },
            ["tiling.nowhere"] = false,
        }, is_known_key)
        expect.equal(resolution.unknown_ids, { "tiling.nowhere" })
        expect.equal(resolution.problems, {
            'the shortcut of "Activate profile 1" names the modifier "hyper", which is none of'
                .. " ctrl, alt, shift, cmd, fn, so it keeps its default",
            'the shortcut of "Fill the screen" names the key "nokey", which macOS does not know,'
                .. " so it keeps its default",
        })
        expect.equal(resolution.shortcut_by_id["profiles.toggle.1"].key, "1")
        expect.equal(resolution.shortcut_by_id["tiling.fill"].key, "return")
    end,

    a_shortcut_that_an_earlier_action_holds_is_left_out = function()
        local resolution = shortcut_registry.resolve(build_registry(), {
            ["tiling.fill"] = { modifiers = { "cmd", "ctrl", "alt" }, key = "Space" },
        }, is_known_key)
        expect.equal(resolution.problems, {
            '"Fill the screen" has no shortcut, because "Show the search" holds'
                .. " Control-Option-Command-Space",
        })
        expect.equal(resolution.shortcut_by_id["tiling.fill"], nil)
    end,

    control_with_a_digit_stays_with_the_desktop_switches_of_macos = function()
        local resolution = shortcut_registry.resolve(build_registry(), {
            ["tiling.fill"] = { modifiers = { "ctrl" }, key = "3" },
        }, is_known_key)
        expect.equal(resolution.problems, {
            '"Fill the screen" has no shortcut, because Control-3 switches desktops in macOS',
        })
    end,

    a_shortcut_reads_as_macos_names_it = function()
        expect.equal(
            shortcut_registry.describe({ modifiers = { "cmd", "shift", "alt" }, key = "left" }),
            "Option-Shift-Command-Left Arrow"
        )
        expect.raises(function()
            local registry = build_registry()
            shortcut_registry.add(registry, { id = "tiling.fill", group = "", title = "" })
        end, 'the shortcut action "tiling.fill" is added twice')
    end,
}
