local shortcut_registry = require("keyboard_shortcuts.core.shortcut_registry")

---The content that the window of the shortcuts shows: the actions by group, each with its shortcut,
---its default and the shortcut of macOS that it collides with, the problems of the last change and
---the shortcut that waits for a choice.
local shortcut_window_model = {}

---@class ShortcutWindowModel
---@field groups table[] each with a name and rows, a row being a ShortcutRow with the macOS
---shortcut that it collides with
---@field problems string[]
---@field pending table|nil the PendingShortcut, without the details of the macOS shortcut

---@param shortcut MacosShortcut|nil
---@return table|nil the part of the shortcut of macOS that the page shows
local function describe_macos(shortcut)
    return shortcut and { id = shortcut.id, name = shortcut.name } or nil
end

---@param center ShortcutCenter
---@param problems string[]
---@param pending PendingShortcut|nil
---@param find_macos_conflict fun(shortcut: Shortcut): MacosShortcut|nil
---@return ShortcutWindowModel
function shortcut_window_model.build_model(center, problems, pending, find_macos_conflict)
    local groups, group_by_name = {}, {}
    for _, row in ipairs(center:list_rows()) do
        local group = group_by_name[row.group]
        if not group then
            group = { name = row.group, rows = {} }
            group_by_name[row.group] = group
            table.insert(groups, group)
        end
        table.insert(group.rows, {
            id = row.id,
            title = row.title,
            shortcut = row.shortcut,
            default = row.default,
            default_text = row.default and shortcut_registry.describe(row.default) or "none",
            is_default = row.is_default,
            macos_conflict = row.shortcut and describe_macos(find_macos_conflict(row.shortcut)),
        })
    end
    local pending_view = nil
    if pending then
        pending_view = {
            id = pending.id,
            shortcut = pending.shortcut,
            text = shortcut_registry.describe(pending.shortcut),
            holder = pending.holder,
            macos = describe_macos(pending.macos),
        }
    end
    return { groups = groups, problems = problems, pending = pending_view }
end

return shortcut_window_model
