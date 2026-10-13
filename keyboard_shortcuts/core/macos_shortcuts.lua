---The shortcuts of macOS in `AppleSymbolicHotKeys` of `com.apple.symbolichotkeys`, which System
---Settings lists under Keyboard, Keyboard Shortcuts, and the one that a shortcut of the tools would
---collide with.
---Each entry holds `enabled` and `value.parameters`: the character, the key code and the flags of
---the modifiers.
local macos_shortcuts = {}

---@class MacosShortcut
---@field id integer the number of the entry in `AppleSymbolicHotKeys`
---@field name string the name that System Settings shows, or a description for an unknown id
---@field ascii integer the character of the key, or 65535 for a key without one
---@field key_code integer
---@field flags integer the modifiers, as the flags of macOS
---@field is_enabled boolean

local FLAG_BY_MODIFIER = {
    shift = 0x20000,
    ctrl = 0x40000,
    alt = 0x80000,
    cmd = 0x100000,
    fn = 0x800000,
}
local FN_FLAG = FLAG_BY_MODIFIER.fn
---The key codes from this one on are the function keys, the arrows and the keys of navigation,
---which macOS stores with the flag of the Fn key.
local FIRST_FUNCTION_KEY_CODE = 96
local NO_KEY = 65535

local NAME_BY_ID = {
    [7] = "Move focus to the menu bar",
    [8] = "Move focus to the Dock",
    [9] = "Move focus to the active or next window",
    [10] = "Move focus to the window toolbar",
    [11] = "Move focus to the floating window",
    [27] = "Move focus to next window",
    [28] = "Save picture of screen as a file",
    [29] = "Copy picture of screen to the clipboard",
    [30] = "Save picture of selected area as a file",
    [31] = "Copy picture of selected area to the clipboard",
    [32] = "Mission Control",
    [33] = "Application windows",
    [34] = "Mission Control, slowly",
    [35] = "Application windows, slowly",
    [36] = "Show Desktop",
    [37] = "Show Desktop, slowly",
    [52] = "Turn Dock hiding on or off",
    [57] = "Move focus to status menus",
    [60] = "Select the previous input source",
    [61] = "Select next source in Input menu",
    [64] = "Show Spotlight search",
    [65] = "Show Finder search window",
    [79] = "Move left a space",
    [80] = "Move left a space, slowly",
    [81] = "Move right a space",
    [82] = "Move right a space, slowly",
    [98] = "Show Help menu",
    [160] = "Show Launchpad",
    [162] = "Show Accessibility controls",
    [175] = "Turn Do Not Disturb on or off",
    [184] = "Screenshot and recording options",
    [190] = "Quick Note",
    [222] = "Turn Stage Manager on or off",
    [237] = "Fill the window",
    [238] = "Center the window",
    [239] = "Return the window to its previous size",
    [240] = "Tile the window to the left",
    [241] = "Tile the window to the right",
    [242] = "Tile the window to the top",
    [243] = "Tile the window to the bottom",
    [248] = "Arrange windows left and right",
    [249] = "Arrange windows right and left",
    [250] = "Arrange windows top and bottom",
    [251] = "Arrange windows bottom and top",
}
for number = 1, 16 do
    NAME_BY_ID[117 + number] = string.format("Switch to Desktop %d", number)
end

---The defaults of the shortcuts that macOS keeps on while `AppleSymbolicHotKeys` leaves them out,
---as the character, the key code and the flags.
local DEFAULT_PARAMETERS_BY_ID = {
    [7] = { NO_KEY, 120, 0x840000 },
    [8] = { NO_KEY, 99, 0x840000 },
    [9] = { NO_KEY, 118, 0x840000 },
    [10] = { NO_KEY, 96, 0x840000 },
    [11] = { NO_KEY, 97, 0x840000 },
    [27] = { 96, 50, 0x100000 },
    [28] = { 51, 20, 0x120000 },
    [29] = { 51, 20, 0x160000 },
    [30] = { 52, 21, 0x120000 },
    [31] = { 52, 21, 0x160000 },
    [57] = { NO_KEY, 100, 0x840000 },
    [98] = { 47, 44, 0x120000 },
    [184] = { 53, 23, 0x120000 },
}

---@param modifiers string[]
---@return integer
function macos_shortcuts.flags_of(modifiers)
    local flags = 0
    for _, modifier in ipairs(modifiers) do
        flags = flags | (FLAG_BY_MODIFIER[modifier] or 0)
    end
    return flags
end

---@param key_code integer
---@param flags integer
---@return integer the flags without the flag of the Fn key that macOS adds to a function key
local function normalize_flags(key_code, flags)
    if key_code >= FIRST_FUNCTION_KEY_CODE then
        return flags & ~FN_FLAG
    end
    return flags
end

---@param id integer
---@return string
function macos_shortcuts.name_of(id)
    return NAME_BY_ID[id] or string.format("the macOS shortcut number %d", id)
end

---@param symbolic_hotkeys table the value of `AppleSymbolicHotKeys`, keyed by the id as a string
---@return MacosShortcut[] the shortcuts with a key, sorted by id
function macos_shortcuts.list(symbolic_hotkeys)
    local shortcuts, is_listed = {}, {}
    for raw_id, entry in pairs(symbolic_hotkeys) do
        local id = tonumber(raw_id)
        local parameters = type(entry) == "table"
            and type(entry.value) == "table"
            and entry.value.parameters
        if id and type(parameters) == "table" and type(parameters[2]) == "number" then
            is_listed[id] = true
            if parameters[2] ~= NO_KEY then
                table.insert(shortcuts, {
                    id = id,
                    name = macos_shortcuts.name_of(id),
                    ascii = parameters[1],
                    key_code = parameters[2],
                    flags = parameters[3] or 0,
                    is_enabled = entry.enabled == true or entry.enabled == 1,
                })
            end
        elseif id then
            is_listed[id] = true
        end
    end
    for id, parameters in pairs(DEFAULT_PARAMETERS_BY_ID) do
        if not is_listed[id] then
            table.insert(shortcuts, {
                id = id,
                name = macos_shortcuts.name_of(id),
                ascii = parameters[1],
                key_code = parameters[2],
                flags = parameters[3],
                is_enabled = true,
            })
        end
    end
    table.sort(shortcuts, function(first, second)
        return first.id < second.id
    end)
    return shortcuts
end

---@param shortcuts MacosShortcut[]
---@param modifiers string[]
---@param key_code integer|nil the key code of the key of the shortcut of the tools
---@return MacosShortcut|nil the shortcut of macOS that is on with the same key and modifiers
function macos_shortcuts.find_conflict(shortcuts, modifiers, key_code)
    if not key_code then
        return nil
    end
    local flags = normalize_flags(key_code, macos_shortcuts.flags_of(modifiers))
    for _, shortcut in ipairs(shortcuts) do
        if
            shortcut.is_enabled
            and shortcut.key_code == key_code
            and normalize_flags(shortcut.key_code, shortcut.flags) == flags
        then
            return shortcut
        end
    end
    return nil
end

return macos_shortcuts
