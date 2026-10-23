local expect = require("tests.expect")
local shortcut_actions = require("desktop_manager.core.shortcut_actions")

---@return ShortcutHandlers handlers that record each call
---@return string[] calls the calls of the handlers, in order
local function record_handler_calls()
    local calls = {}
    local function record(name)
        return function(...)
            local arguments = { name }
            for index = 1, select("#", ...) do
                table.insert(arguments, tostring(select(index, ...)))
            end
            table.insert(calls, table.concat(arguments, " "))
        end
    end
    return {
        toggle_profile = record("toggle_profile"),
        deactivate_profile = record("deactivate_profile"),
        clear_profile = record("clear_profile"),
        press_app_number = record("press_app_number"),
        reset_app_numbers = record("reset_app_numbers"),
        toggle_window_search = record("toggle_window_search"),
    },
        calls
end

return {
    the_actions_come_in_the_order_that_decides_which_one_keeps_a_shortcut = function()
        local handlers = record_handler_calls()
        local ids = {}
        for _, action in ipairs(shortcut_actions.list(2, 2, handlers)) do
            table.insert(ids, action.id)
        end
        expect.equal(ids, {
            "profiles.toggle.1",
            "profiles.toggle.2",
            "profiles.deactivate",
            "profiles.clear.1",
            "profiles.clear.2",
            "app_numbers.press.1",
            "app_numbers.press.2",
            "app_numbers.reset",
            "window_search.toggle",
        })
    end,

    each_action_has_its_default_shortcut_and_runs_its_handler = function()
        local handlers, calls = record_handler_calls()
        local defaults = {}
        for _, action in ipairs(shortcut_actions.list(1, 1, handlers)) do
            table.insert(
                defaults,
                table.concat(action.default.modifiers, "+") .. " " .. action.default.key
            )
            action.on_press("the binding")
        end
        expect.equal(defaults, {
            "cmd+alt+shift 1",
            "cmd+alt+shift 0",
            "ctrl+alt+cmd 1",
            "ctrl+alt 1",
            "ctrl+alt 0",
            "ctrl+alt+cmd space",
        })
        expect.equal(calls, {
            "toggle_profile 1",
            "deactivate_profile",
            "clear_profile 1",
            "press_app_number 1 the binding",
            "reset_app_numbers",
            "toggle_window_search",
        })
    end,
}
