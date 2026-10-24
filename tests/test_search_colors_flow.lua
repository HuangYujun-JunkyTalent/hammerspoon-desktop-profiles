local controller_world = require("tests.controller_world")
local expect = require("tests.expect")

return {
    a_highlight_color_of_the_setting_marks_the_selection = function()
        local selection = { hex = "#2E8B57", alpha = 0.9 }
        local world =
            controller_world.start_world({ search_highlight_colors = { selection = selection } })
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        local fill = nil
        for _, element in ipairs(world.overlay.elements) do
            if element.id == "selection" then
                fill = element.fillColor
            end
        end
        expect.equal(fill, selection)
        expect.raises(function()
            controller_world.start_world({ search_highlight_colors = { selected = selection } })
        end, 'names "selected", which is none of')
    end,

    a_color_from_the_window_of_the_colors_shows_in_the_next_search = function()
        local world, controller = controller_world.start_world()
        controller_world.find_menu_item(world, "Search colors…").fn()
        expect.equal(
            controller.color_window.model.colors.selection,
            { hex = "#3373F2", alpha = 0.95 }
        )
        local chosen = controller.color_window.model.colors
        chosen.selection = { hex = "#2E8B57", alpha = 0.9 }
        world.post_to_webview("colors", { kind = "set", colors = chosen })
        expect.equal(world.saved_json.highlight_colors.selection, { hex = "#2E8B57", alpha = 0.9 })
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        local fill = nil
        for _, element in ipairs(world.overlay.elements) do
            if element.id == "selection" then
                fill = element.fillColor
            end
        end
        expect.equal(fill, { hex = "#2E8B57", alpha = 0.9 })
        world.hotkey_by_shortcut[controller_world.SEARCH_SHORTCUT]()
        world.post_to_webview("colors", { kind = "restore" })
        expect.equal(controller.state.highlight_colors, {})
        world.post_to_webview("colors", { kind = "done" })
        expect.equal(controller.color_window, nil)
    end,
}
