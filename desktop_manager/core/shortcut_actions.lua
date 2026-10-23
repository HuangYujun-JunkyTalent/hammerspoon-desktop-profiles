---The actions of the desktop manager that the center of the shortcuts binds, with their default
---shortcuts.
local shortcut_actions = {}

---The methods of the controller that the actions run.
---@class ShortcutHandlers
---@field toggle_profile fun(number: integer)
---@field deactivate_profile fun()
---@field clear_profile fun(number: integer)
---@field press_app_number fun(app_number: integer, binding: ShortcutBinding)
---@field reset_app_numbers fun()
---@field toggle_window_search fun()

---The actions of the profiles, the application numbers and the search of the windows, with their
---default shortcuts.
---@param profile_count integer
---@param app_number_count integer
---@param handlers ShortcutHandlers
---@return RegisteredAction[]
function shortcut_actions.list(profile_count, app_number_count, handlers)
    local actions = {}
    local profile_modifiers = { "cmd", "alt", "shift" }
    for number = 1, profile_count do
        table.insert(actions, {
            id = "profiles.toggle." .. number,
            group = "Profiles",
            title = string.format(
                "Activate profile %d, or deactivate it while it is active",
                number
            ),
            default = { modifiers = profile_modifiers, key = tostring(number) },
            on_press = function()
                handlers.toggle_profile(number)
            end,
        })
    end
    table.insert(actions, {
        id = "profiles.deactivate",
        group = "Profiles",
        title = "Deactivate the active profile",
        default = { modifiers = profile_modifiers, key = "0" },
        on_press = function()
            handlers.deactivate_profile()
        end,
    })
    -- Control-Option-Command with a digit is free between the application numbers and the profiles,
    -- and the profile is cleared only after the user agrees in a dialog.
    for number = 1, profile_count do
        table.insert(actions, {
            id = "profiles.clear." .. number,
            group = "Profiles",
            title = string.format(
                "Clear profile %d, after a confirmation, so that it forgets its saved layouts",
                number
            ),
            default = { modifiers = { "ctrl", "alt", "cmd" }, key = tostring(number) },
            on_press = function()
                handlers.clear_profile(number)
            end,
        })
    end
    local app_modifiers = { "ctrl", "alt" }
    for app_number = 1, app_number_count do
        table.insert(actions, {
            id = "app_numbers.press." .. app_number,
            group = "Application numbers",
            title = string.format(
                "Show the windows of application %d, and go to the selection on release",
                app_number
            ),
            default = { modifiers = app_modifiers, key = tostring(app_number) },
            on_press = function(binding)
                handlers.press_app_number(app_number, binding)
            end,
        })
    end
    table.insert(actions, {
        id = "app_numbers.reset",
        group = "Application numbers",
        title = "Return every application number to the default",
        default = { modifiers = app_modifiers, key = "0" },
        on_press = function()
            handlers.reset_app_numbers()
        end,
    })
    table.insert(actions, {
        id = "window_search.toggle",
        group = "Window search",
        title = "Show the search of the windows, or close it",
        default = { modifiers = { "ctrl", "alt", "cmd" }, key = "space" },
        on_press = function()
            handlers.toggle_window_search()
        end,
    })
    return actions
end

return shortcut_actions
