local desktop_shortcuts = require("desktop_manager.core.desktop_shortcuts")
local expect = require("tests.expect")

---The entry of "Switch to Desktop 6" as Control-Option-Shift-Command-6, as macOS stores it.
local function control_6()
    return { enabled = true, value = { parameters = { 65535, 22, 1966080 }, type = "standard" } }
end

return {
    a_shortcut_is_on_as_control_and_the_number = function()
        expect.equal(desktop_shortcuts.is_on({ ["123"] = control_6() }, 6), true)
    end,

    a_missing_shortcut_is_off = function()
        expect.equal(desktop_shortcuts.is_on({ ["122"] = control_6() }, 6), false)
    end,

    a_turned_off_shortcut_is_off = function()
        local entry = control_6()
        entry.enabled = false
        expect.equal(desktop_shortcuts.is_on({ ["123"] = entry }, 6), false)
    end,

    a_shortcut_on_other_keys_is_off = function()
        local entry = control_6()
        entry.value.parameters[3] = 524288
        expect.equal(desktop_shortcuts.is_on({ ["123"] = entry }, 6), false)
    end,

    desktop_10_is_on_as_control_and_0 = function()
        local entry =
            { enabled = true, value = { parameters = { 65535, 29, 1966080 }, type = "standard" } }
        expect.equal(desktop_shortcuts.is_on({ ["127"] = entry }, 10), true)
        expect.equal(desktop_shortcuts.key_of(10), "0")
        expect.equal(desktop_shortcuts.key_of(9), "9")
    end,
}
