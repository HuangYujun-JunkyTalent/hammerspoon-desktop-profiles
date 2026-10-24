local app_numbers = require("desktop_manager.core.app_numbers")
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
---@field choose_app_number fun(app_number: integer, bundle_id: string, app_name: string)
---@field release_app_number fun(app_number: integer)
---@field clear_profile fun(number: integer)
---@field open_app_pool_window fun()
---@field open_shortcut_window fun()
---@field open_color_window fun()

---The numbers of the active profile, or of profile 0 while no profile is active, each with a
---submenu that gives it to the application that was in front when the menu opened, or returns it to
---the default.
---@param profile Profile
---@param app_number_count integer
---@param actions StatusMenuActions
---@return table[] the items of an hs.menubar submenu
local function build_app_number_items(profile, app_number_count, actions)
    local front = hs.application.frontmostApplication()
    local front_bundle_id = front and front:bundleID()
    local front_name = front and front:name()
    local items = {}
    for app_number = 1, app_number_count do
        local entry = app_numbers.find_by_number(profile.app_numbers, app_number)
        local holder = entry and entry.app_name or "no application"
        local chosen = entry and entry.is_chosen_by_user and ", chosen" or ""
        table.insert(items, {
            title = string.format("%d  %s%s", app_number, holder, chosen),
            menu = {
                {
                    title = string.format("Give %d to %s", app_number, front_name or "—"),
                    disabled = front_bundle_id == nil,
                    fn = function()
                        actions.choose_app_number(app_number, front_bundle_id, front_name)
                    end,
                },
                {
                    title = string.format("Return %d to the default", app_number),
                    disabled = entry == nil or not entry.is_chosen_by_user,
                    fn = function()
                        actions.release_app_number(app_number)
                    end,
                },
            },
        })
    end
    return items
end

---One item per profile that clears its saved layouts, after a confirmation.
---@param state State
---@param settings Settings
---@param actions StatusMenuActions
---@return table[] the items of an hs.menubar submenu
local function build_clear_items(state, settings, actions)
    local items = {}
    for number = 1, settings.profile_count do
        local profile = profile_state.profile_or_default(state, number)
        table.insert(items, {
            title = string.format("%d  %s…", number, profile.name),
            disabled = not profile_state.has_arrangements(state, number),
            fn = function()
                actions.clear_profile(number)
            end,
        })
    end
    return items
end

---One item per profile that activates it, or deactivates it while it is active, with a check
---mark on the active profile.
---@param state State
---@param settings Settings
---@param actions StatusMenuActions
---@return table[] the items of an hs.menubar menu
local function build_profile_items(state, settings, actions)
    local items = {}
    for number = 1, settings.profile_count do
        local profile = profile_state.profile_or_default(state, number)
        table.insert(items, {
            title = string.format("%d  %s", number, profile.name),
            checked = state.active_profile_number == number,
            fn = function()
                actions.toggle_profile(number)
            end,
        })
    end
    return items
end

---One item per way of matching monitor configurations, with a check mark on the way in use.
---@param state State
---@param actions StatusMenuActions
---@return table[] the items of an hs.menubar submenu
local function build_monitor_matching_items(state, actions)
    local items = {}
    for _, matching in ipairs(monitor_matching.all()) do
        table.insert(items, {
            title = monitor_matching.label_of(matching),
            checked = state.monitor_matching == matching,
            fn = function()
                actions.set_monitor_matching(matching)
            end,
        })
    end
    return items
end

---@param state State
---@param settings Settings
---@param actions StatusMenuActions
---@return table[] the items of an hs.menubar menu
local function build_items(state, settings, actions)
    local items = build_profile_items(state, settings, actions)
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
    table.insert(
        items,
        { title = "Clear profile", menu = build_clear_items(state, settings, actions) }
    )
    table.insert(items, { title = "Managed applications…", fn = actions.open_app_pool_window })
    table.insert(items, { title = "Keyboard shortcuts…", fn = actions.open_shortcut_window })
    table.insert(items, { title = "Search colors…", fn = actions.open_color_window })
    table.insert(items, {
        title = "Same monitor configuration by",
        menu = build_monitor_matching_items(state, actions),
    })
    local numbering_profile =
        profile_state.profile_or_default(state, profile_state.find_numbering_profile_number(state))
    table.insert(items, {
        title = "Application numbers",
        menu = build_app_number_items(numbering_profile, settings.app_number_count, actions),
    })
    table.insert(items, { title = "-" })
    table.insert(items, {
        title = state.is_active_profile_paused and "Save arrangement now and end the pause"
            or "Save arrangement now",
        fn = actions.save_arrangement,
    })
    table.insert(
        items,
        { title = "Print diagnostics to the console", fn = actions.print_diagnostics }
    )
    return items
end

---@param menubar table an hs.menubar
---@param read_state fun(): State the state when the menu opens
---@param settings Settings
---@param actions StatusMenuActions
function status_menu.show(menubar, read_state, settings, actions)
    local state = read_state()
    local number = state.active_profile_number
    if number then
        menubar:setTitle(string.format("%s %d", MENU_BAR_SYMBOL, number))
        menubar:setTooltip(profile_state.profile_or_default(state, number).name)
    else
        menubar:setTitle(MENU_BAR_SYMBOL)
        menubar:setTooltip("No desktop profile is active")
    end
    menubar:setMenu(function()
        return build_items(read_state(), settings, actions)
    end)
end

return status_menu
