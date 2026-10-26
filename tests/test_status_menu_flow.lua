local controller_world = require("tests.controller_world")
local expect = require("tests.expect")

---@param world table
---@return string[] the titles of the menu bar item after the profiles, with "-" for a separator
local function read_titles_after_profiles(world)
    local titles = {}
    for _, item in ipairs(world.menu_builder()) do
        if not item.title:match("^%d  ") then
            table.insert(titles, item.title)
        end
    end
    return titles
end

return {
    the_menu_groups_its_items_and_names_the_active_profile_in_its_actions = function()
        local world = controller_world.start_world()
        expect.equal(read_titles_after_profiles(world), {
            "-",
            "Deactivate profile",
            "Rename profile…",
            "Save layout now",
            "Clear a profile",
            "-",
            "Application numbers",
            "-",
            "Settings…",
            "Managed applications…",
            "Keyboard shortcuts…",
            "Print diagnostics to the console",
        })
        expect.equal(controller_world.find_menu_item(world, "Deactivate profile").disabled, true)
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        local titles = read_titles_after_profiles(world)
        expect.equal(
            { titles[2], titles[3], titles[4] },
            {
                "Deactivate “Profile 1”",
                "Rename “Profile 1”…",
                "Save layout of “Profile 1” now",
            }
        )
        expect.equal(
            controller_world.find_menu_item(world, "Deactivate “Profile 1”").disabled,
            false
        )
    end,
}
