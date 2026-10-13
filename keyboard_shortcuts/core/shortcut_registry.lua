---The global keyboard shortcuts of the tools in one place.
---Each utility adds its actions with their default shortcuts, and one table of overrides changes
---any of them, so that no utility keeps shortcut settings of its own.
local shortcut_registry = {}

---A keyboard shortcut: the names of its modifiers and the name of its key, as hs.hotkey takes them.
---@class Shortcut
---@field modifiers string[]
---@field key string

---@class ShortcutAction
---@field id string such as "profiles.toggle.3", the name of the action in the file of overrides
---@field group string the utility, such as "Profiles", under which the window lists the action
---@field title string what the shortcut does, such as "Activate profile 3, or deactivate it"
---@field default Shortcut|nil

---@class ShortcutRegistry
---@field actions ShortcutAction[] in the order the utilities added them
---@field action_by_id table<string, ShortcutAction>

---@class ShortcutResolution
---@field shortcut_by_id table<string, Shortcut> the shortcut of each action that has one
---@field problems string[] the overrides of actions that the registry left out, and why
---@field unknown_ids string[] the overrides that name no action, sorted, which may belong to a
---utility that registers later

---The order in which macOS shows the modifiers of a shortcut.
local MODIFIER_ORDER = { "ctrl", "alt", "shift", "cmd", "fn" }
local MODIFIER_NAMES = {
    ctrl = "Control",
    alt = "Option",
    shift = "Shift",
    cmd = "Command",
    fn = "Fn",
}
local KEY_NAMES = {
    space = "Space",
    ["return"] = "Return",
    padenter = "Enter",
    tab = "Tab",
    escape = "Escape",
    delete = "Delete",
    forwarddelete = "Forward Delete",
    left = "Left Arrow",
    right = "Right Arrow",
    up = "Up Arrow",
    down = "Down Arrow",
    home = "Home",
    ["end"] = "End",
    pageup = "Page Up",
    pagedown = "Page Down",
}

---@return ShortcutRegistry
function shortcut_registry.new()
    return { actions = {}, action_by_id = {} }
end

---@param registry ShortcutRegistry
---@param action ShortcutAction
function shortcut_registry.add(registry, action)
    if registry.action_by_id[action.id] then
        error(string.format("the shortcut action %q is added twice", action.id), 2)
    end
    table.insert(registry.actions, action)
    registry.action_by_id[action.id] = action
end

---@param value any
---@return string|nil message why the value is no shortcut, or nil for a shortcut
function shortcut_registry.check(value)
    if type(value) ~= "table" or type(value.modifiers) ~= "table" then
        return "gives no list of modifiers"
    end
    if type(value.key) ~= "string" or value.key == "" then
        return "gives no key"
    end
    local is_seen = {}
    for _, modifier in ipairs(value.modifiers) do
        if not MODIFIER_NAMES[modifier] then
            return string.format(
                "names the modifier %q, which is none of %s",
                tostring(modifier),
                table.concat(MODIFIER_ORDER, ", ")
            )
        end
        if is_seen[modifier] then
            return string.format("names the modifier %q twice", modifier)
        end
        is_seen[modifier] = true
    end
    return nil
end

---@param shortcut Shortcut
---@return string the same text for two shortcuts that macOS treats as one
local function combination_key(shortcut)
    local held = {}
    for _, modifier in ipairs(shortcut.modifiers) do
        held[modifier] = true
    end
    local parts = {}
    for _, modifier in ipairs(MODIFIER_ORDER) do
        if held[modifier] then
            table.insert(parts, modifier)
        end
    end
    table.insert(parts, shortcut.key:lower())
    return table.concat(parts, "+")
end

---@param first Shortcut
---@param second Shortcut
---@return boolean whether macOS treats the two as one shortcut
function shortcut_registry.is_same_combination(first, second)
    return combination_key(first) == combination_key(second)
end

---Control with a digit is "Switch to Desktop N" of macOS, which the desktop manager presses.
---@param shortcut Shortcut
---@return boolean
function shortcut_registry.is_reserved(shortcut)
    return #shortcut.modifiers == 1
        and shortcut.modifiers[1] == "ctrl"
        and shortcut.key:match("^%d$") ~= nil
end

---@param shortcut Shortcut
---@return string such as "Control-Option-Command-Space"
function shortcut_registry.describe(shortcut)
    local held = {}
    for _, modifier in ipairs(shortcut.modifiers) do
        held[modifier] = true
    end
    local parts = {}
    for _, modifier in ipairs(MODIFIER_ORDER) do
        if held[modifier] then
            table.insert(parts, MODIFIER_NAMES[modifier])
        end
    end
    table.insert(parts, KEY_NAMES[shortcut.key:lower()] or shortcut.key:upper())
    return table.concat(parts, "-")
end

---Gives each action its default shortcut, or the shortcut of its override.
---An override `false` leaves the action without a shortcut.
---An override that is no shortcut, or names a key that `is_known_key` rejects, leaves the default.
---A shortcut that an earlier action holds, or that is Control with a digit, leaves the action
---without a shortcut.
---@param registry ShortcutRegistry
---@param overrides table<string, Shortcut|false>
---@param is_known_key fun(key: string): boolean
---@return ShortcutResolution
function shortcut_registry.resolve(registry, overrides, is_known_key)
    local problems = {}
    local unknown_ids = {}
    for id in pairs(overrides) do
        if not registry.action_by_id[id] then
            table.insert(unknown_ids, id)
        end
    end
    table.sort(unknown_ids)
    local shortcut_by_id, holder_by_combination = {}, {}
    for _, action in ipairs(registry.actions) do
        local shortcut = action.default
        local override = overrides[action.id]
        if override == false then
            shortcut = nil
        elseif override ~= nil then
            local message = shortcut_registry.check(override)
            if not message and not is_known_key(override.key) then
                message = string.format("names the key %q, which macOS does not know", override.key)
            end
            if message then
                table.insert(
                    problems,
                    string.format(
                        "the shortcut of %q %s, so it keeps its default",
                        action.title,
                        message
                    )
                )
            else
                shortcut = override
            end
        end
        if shortcut and shortcut_registry.is_reserved(shortcut) then
            table.insert(
                problems,
                string.format(
                    "%q has no shortcut, because %s switches desktops in macOS",
                    action.title,
                    shortcut_registry.describe(shortcut)
                )
            )
            shortcut = nil
        end
        if shortcut then
            local combination = combination_key(shortcut)
            local holder = holder_by_combination[combination]
            if holder then
                table.insert(
                    problems,
                    string.format(
                        "%q has no shortcut, because %q holds %s",
                        action.title,
                        holder.title,
                        shortcut_registry.describe(shortcut)
                    )
                )
                shortcut = nil
            else
                holder_by_combination[combination] = action
            end
        end
        shortcut_by_id[action.id] = shortcut
    end
    return { shortcut_by_id = shortcut_by_id, problems = problems, unknown_ids = unknown_ids }
end

return shortcut_registry
