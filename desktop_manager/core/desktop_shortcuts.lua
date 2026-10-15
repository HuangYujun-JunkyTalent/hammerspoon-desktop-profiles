---The macOS shortcuts "Switch to Desktop N", which the desktop manager presses as
---Control-Option-Shift-Command-N, and as Control-Option-Shift-Command-0 for desktop 10.
---Four modifiers leave the shortcuts to no other application, while Control alone with a number is
---taken by many applications.
---macOS keeps them in `AppleSymbolicHotKeys` of `com.apple.symbolichotkeys`, under the id 117 + N.
local desktop_shortcuts = {}

desktop_shortcuts.HIGHEST_NUMBER = 10

local FIRST_ID_BEFORE_DESKTOP_1 = 117
---The modifiers of the shortcuts, as hs.eventtap takes them and as the flags of macOS.
desktop_shortcuts.MODIFIERS = { "ctrl", "alt", "shift", "cmd" }
desktop_shortcuts.FLAGS = 0x40000 | 0x80000 | 0x20000 | 0x100000
---The name of the modifiers in a message, such as "Control-Option-Shift-Command-3".
desktop_shortcuts.MODIFIER_TEXT = "Control-Option-Shift-Command"
---The key codes of the keys 1 to 9 and 0 of an ANSI keyboard.
local KEY_CODES = { 18, 19, 20, 21, 23, 22, 26, 28, 25, 29 }

---@param number integer from 1 to 10
---@return string the key that the shortcut of the desktop presses with Control
function desktop_shortcuts.key_of(number)
    return number == 10 and "0" or tostring(number)
end

---@param symbolic_hotkeys table the value of `AppleSymbolicHotKeys`
---@param number integer
---@return boolean whether "Switch to Desktop N" is on with the modifiers and the number
function desktop_shortcuts.is_on(symbolic_hotkeys, number)
    local entry = symbolic_hotkeys[tostring(FIRST_ID_BEFORE_DESKTOP_1 + number)]
    if type(entry) ~= "table" or entry.enabled ~= true then
        return false
    end
    local parameters = type(entry.value) == "table" and entry.value.parameters or {}
    return parameters[2] == KEY_CODES[number] and parameters[3] == desktop_shortcuts.FLAGS
end

return desktop_shortcuts
