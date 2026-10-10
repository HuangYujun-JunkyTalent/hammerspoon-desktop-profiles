local monitor_matching = require("desktop_manager.core.monitor_matching")
local profile_state = require("desktop_manager.core.profile_state")

local status_menu = {}

local MENU_BAR_SYMBOL = "◧"

---@class StatusMenuActions
---@field toggle_profile fun(number: integer)
---@field deactivate_profile fun()
---@field rename_active_profile fun()
---@field set_monitor_matching fun(matching: string)
---@field save_arrangement fun()
---@field print_diagnostics fun()

---@param state State
---@param profile_count integer
---@param actions StatusMenuActions
---@return table[] the items of an hs.menubar menu
local function build_items(state, profile_count, actions)
    local items = {}
    for number = 1, profile_count do
        local profile = profile_state.profile_or_default(state, number)
        table.insert(items, {
            title = string.format("%d  %s", number, profile.name),
            checked = state.active_profile_number == number,
            fn = function()
                actions.toggle_profile(number)
            end,
        })
    end
    table.insert(items, { title = "-" })
    table.insert(items, {
        title = "Deactivate profile",
        disabled = state.active_profile_number == nil,
        fn = actions.deactivate_profile,
    })
    table.insert(items, {
        title = "Rename active profile…",
        disabled = state.active_profile_number == nil,
        fn = actions.rename_active_profile,
    })
    local matching_items = {}
    for _, matching in ipairs(monitor_matching.all()) do
        table.insert(matching_items, {
            title = monitor_matching.label_of(matching),
            checked = state.monitor_matching == matching,
            fn = function()
                actions.set_monitor_matching(matching)
            end,
        })
    end
    table.insert(items, { title = "Same monitor configuration by", menu = matching_items })
    table.insert(items, { title = "-" })
    table.insert(items, { title = "Save arrangement now", fn = actions.save_arrangement })
    table.insert(
        items,
        { title = "Print diagnostics to the console", fn = actions.print_diagnostics }
    )
    return items
end

---@param menubar table an hs.menubar
---@param state State
---@param profile_count integer
---@param actions StatusMenuActions
function status_menu.show(menubar, state, profile_count, actions)
    local number = state.active_profile_number
    if number then
        menubar:setTitle(string.format("%s %d", MENU_BAR_SYMBOL, number))
        menubar:setTooltip(profile_state.profile_or_default(state, number).name)
    else
        menubar:setTitle(MENU_BAR_SYMBOL)
        menubar:setTooltip("No desktop profile is active")
    end
    menubar:setMenu(function()
        return build_items(state, profile_count, actions)
    end)
end

return status_menu
