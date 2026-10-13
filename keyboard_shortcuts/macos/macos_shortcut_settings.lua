local macos_shortcuts = require("keyboard_shortcuts.core.macos_shortcuts")

---Reads the shortcuts of macOS, and turns one off with `tools/disable_macos_shortcut.sh`.
local macos_shortcut_settings = {}

local DISABLE_SCRIPT = (
    debug
        .getinfo(1, "S").source
        :match("^@(.*)/keyboard_shortcuts/macos/macos_shortcut_settings%.lua$") or "."
) .. "/tools/disable_macos_shortcut.sh"

---@return table|nil the shortcuts of macOS, `AppleSymbolicHotKeys`, or nil when they cannot be read
function macos_shortcut_settings.read_symbolic_hotkeys()
    local output, is_successful = hs.execute("defaults export com.apple.symbolichotkeys -")
    if not is_successful then
        return nil
    end
    local preferences = hs.plist.readString(output)
    return type(preferences) == "table" and preferences.AppleSymbolicHotKeys or nil
end

---@return MacosShortcut[]
function macos_shortcut_settings.list()
    return macos_shortcuts.list(macos_shortcut_settings.read_symbolic_hotkeys() or {})
end

---@param modifiers string[]
---@param key string a name of hs.keycodes.map
---@return MacosShortcut|nil the shortcut of macOS that is on with the same keys
function macos_shortcut_settings.find_conflict(modifiers, key)
    return macos_shortcuts.find_conflict(
        macos_shortcut_settings.list(),
        modifiers,
        hs.keycodes.map[key]
    )
end

---Turns the shortcut of macOS off and keeps its keys, as the user chose in the window of the
---shortcuts.
---@param shortcut MacosShortcut
---@param on_done fun(error_message: string|nil)
function macos_shortcut_settings.turn_off(shortcut, on_done)
    local task = hs.task.new("/bin/sh", function(exit_code, _, standard_error)
        if exit_code ~= 0 then
            on_done(
                string.format(
                    'The macOS shortcut "%s" could not be turned off: %s',
                    shortcut.name,
                    tostring(standard_error)
                )
            )
            return
        end
        on_done(nil)
    end, {
        DISABLE_SCRIPT,
        tostring(shortcut.id),
        tostring(shortcut.ascii),
        tostring(shortcut.key_code),
        tostring(shortcut.flags),
    })
    if not task or not task:start() then
        on_done(string.format('The macOS shortcut "%s" could not be turned off', shortcut.name))
    end
end

return macos_shortcut_settings
