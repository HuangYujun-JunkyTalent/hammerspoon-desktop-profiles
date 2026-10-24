local shortcut_registry = require("keyboard_shortcuts.core.shortcut_registry")

---Binds the global shortcuts of every tool, from one registry and one file of overrides.
---A tool registers its actions with a function for each, and the center binds the shortcut that
---the registry resolves, so that a change of a shortcut needs no change of the tool.
local shortcut_center = {}

local NOTIFICATION_TITLE = "Keyboard shortcuts"

---The shortcut that an action has now, and its hs.hotkey.
---@class ShortcutBinding
---@field shortcut Shortcut
---@field hotkey table the hs.hotkey

---@class RegisteredAction: ShortcutAction
---@field on_press fun(binding: ShortcutBinding)

---@class ShortcutRow
---@field id string
---@field group string
---@field title string
---@field shortcut Shortcut|nil
---@field default Shortcut|nil
---@field is_default boolean

---@class ShortcutCenter
---@field registry ShortcutRegistry
---@field on_press_by_id table<string, fun(binding: ShortcutBinding)>
---@field overrides table<string, Shortcut|false>
---@field file_path string|nil the JSON file of the overrides, or nil to keep them in memory
---@field binding_by_id table<string, ShortcutBinding>
---@field is_turned_off boolean
---@field log table an hs.logger
local ShortcutCenter = {}
ShortcutCenter.__index = ShortcutCenter

---@param key string
---@return boolean
local function is_known_key(key)
    return hs.keycodes.map[key] ~= nil
end

---@param file_path string|nil
---@return table<string, Shortcut|false> overrides
---@return string|nil warning
local function read_overrides(file_path)
    if not file_path or not hs.fs.attributes(file_path) then
        return {}, nil
    end
    local overrides = hs.json.read(file_path)
    if type(overrides) ~= "table" then
        return {}, string.format("%s holds no table of shortcuts, so the defaults apply", file_path)
    end
    return overrides, nil
end

---@param file_path string|nil the JSON file of the overrides, such as
---`~/.hammerspoon/keyboard-shortcuts.json`, or nil to keep the overrides in memory
---@return ShortcutCenter
function shortcut_center.new(file_path)
    local center = setmetatable({
        registry = shortcut_registry.new(),
        on_press_by_id = {},
        file_path = file_path,
        binding_by_id = {},
        is_turned_off = false,
        log = hs.logger.new("shortcuts", "info"),
    }, ShortcutCenter)
    local overrides, warning = read_overrides(file_path)
    center.overrides = overrides
    if warning then
        center:report({ warning })
    end
    return center
end

---@param problems string[]
function ShortcutCenter:report(problems)
    for _, problem in ipairs(problems) do
        self.log.w(problem)
    end
    if #problems > 0 then
        local message = problems[1]
        if #problems > 1 then
            message =
                string.format("%s (%d problems in the Hammerspoon console)", problems[1], #problems)
        end
        hs.notify.new({ title = NOTIFICATION_TITLE, informativeText = message }):send()
    end
end

---Deletes every hotkey, resolves the shortcuts again and binds them.
---@return string[] problems
function ShortcutCenter:rebind()
    for _, binding in pairs(self.binding_by_id) do
        binding.hotkey:delete()
    end
    self.binding_by_id = {}
    local resolution = shortcut_registry.resolve(self.registry, self.overrides, is_known_key)
    for _, action in ipairs(self.registry.actions) do
        local shortcut = resolution.shortcut_by_id[action.id]
        if shortcut then
            local binding = { shortcut = shortcut }
            local on_press = self.on_press_by_id[action.id]
            binding.hotkey = hs.hotkey.bind(shortcut.modifiers, shortcut.key, function()
                on_press(binding)
            end)
            if self.is_turned_off then
                binding.hotkey:disable()
            end
            self.binding_by_id[action.id] = binding
        end
    end
    return resolution.problems
end

---Adds the actions of one tool and binds their shortcuts.
---@param actions RegisteredAction[]
function ShortcutCenter:register(actions)
    for _, action in ipairs(actions) do
        shortcut_registry.add(self.registry, {
            id = action.id,
            group = action.group,
            title = action.title,
            default = action.default,
        })
        self.on_press_by_id[action.id] = action.on_press
    end
    self:report(self:rebind())
end

---@param id string
---@return Shortcut|nil the shortcut that the action has now
function ShortcutCenter:find_shortcut(id)
    local binding = self.binding_by_id[id]
    return binding and binding.shortcut
end

---Saves the overrides, and once the file is written makes them the overrides of the center, binds
---the shortcuts again and reports their problems.
---When the write fails, the center keeps the overrides that it had.
---@param center ShortcutCenter
---@param overrides table<string, Shortcut|false>
---@return string[] problems
local function save_and_rebind(center, overrides)
    if center.file_path and not hs.json.write(overrides, center.file_path, true, true) then
        return { string.format("the shortcuts could not be written to %s", center.file_path) }
    end
    center.overrides = overrides
    local problems = center:rebind()
    center:report(problems)
    return problems
end

---Gives an action a new shortcut, no shortcut, or its default again, and saves the overrides.
---@param id string
---@param value Shortcut|false|nil a shortcut, false for none, or nil for the default
---@return string[] problems
function ShortcutCenter:set_override(id, value)
    if not self.registry.action_by_id[id] then
        return { string.format("no shortcut action is named %q", id) }
    end
    local overrides = {}
    for other_id, other_value in pairs(self.overrides) do
        overrides[other_id] = other_value
    end
    overrides[id] = value
    return save_and_rebind(self, overrides)
end

---@param shortcut Shortcut
---@param except_id string the action that would take the shortcut
---@return ShortcutAction|nil the other action that has the shortcut now
function ShortcutCenter:find_holder(shortcut, except_id)
    for _, action in ipairs(self.registry.actions) do
        local current = self:find_shortcut(action.id)
        if
            action.id ~= except_id
            and current
            and shortcut_registry.is_same_combination(current, shortcut)
        then
            return action
        end
    end
    return nil
end

---Gives every action its default shortcut again, and saves the empty overrides.
---@return string[] problems
function ShortcutCenter:reset_all()
    return save_and_rebind(self, {})
end

---Reports the overrides that name no action, once every tool has registered.
function ShortcutCenter:check_overrides()
    local resolution = shortcut_registry.resolve(self.registry, self.overrides, is_known_key)
    local problems = {}
    for _, id in ipairs(resolution.unknown_ids) do
        table.insert(
            problems,
            string.format("%s names the action %q, which no tool has", self.file_path, id)
        )
    end
    self:report(problems)
end

---Turns every shortcut off, as while the window records a new shortcut, so that pressing a
---shortcut of the tools records it instead of running it.
function ShortcutCenter:turn_off()
    self.is_turned_off = true
    for _, binding in pairs(self.binding_by_id) do
        binding.hotkey:disable()
    end
end

---Turns every shortcut on again.
function ShortcutCenter:turn_on()
    self.is_turned_off = false
    for _, binding in pairs(self.binding_by_id) do
        binding.hotkey:enable()
    end
end

---@return ShortcutRow[] every action, in the order of the registry
function ShortcutCenter:list_rows()
    local rows = {}
    for _, action in ipairs(self.registry.actions) do
        table.insert(rows, {
            id = action.id,
            group = action.group,
            title = action.title,
            shortcut = self:find_shortcut(action.id),
            default = action.default,
            is_default = self.overrides[action.id] == nil,
        })
    end
    return rows
end

return shortcut_center
