---The macOS shortcuts "Switch to Desktop N", which the desktop manager presses as Control-N, and
---as Control-0 for desktop 10.
---macOS keeps them in `AppleSymbolicHotKeys` of `com.apple.symbolichotkeys`, under the id 117 + N.
local desktop_shortcuts = {}

desktop_shortcuts.HIGHEST_NUMBER = 10

local FIRST_ID_BEFORE_DESKTOP_1 = 117
local CONTROL_FLAG = 262144
---The key codes of the keys 1 to 9 and 0 of an ANSI keyboard.
local KEY_CODES = { 18, 19, 20, 21, 23, 22, 26, 28, 25, 29 }

---@param number integer from 1 to 10
---@return string the key that the shortcut of the desktop presses with Control
function desktop_shortcuts.key_of(number)
    return number == 10 and "0" or tostring(number)
end

---@param symbolic_hotkeys table the value of `AppleSymbolicHotKeys`
---@param number integer
---@return boolean whether "Switch to Desktop N" is on as Control-N
function desktop_shortcuts.is_on(symbolic_hotkeys, number)
    local entry = symbolic_hotkeys[tostring(FIRST_ID_BEFORE_DESKTOP_1 + number)]
    if type(entry) ~= "table" or entry.enabled ~= true then
        return false
    end
    local parameters = type(entry.value) == "table" and entry.value.parameters or {}
    return parameters[2] == KEY_CODES[number] and parameters[3] == CONTROL_FLAG
end

return desktop_shortcuts
