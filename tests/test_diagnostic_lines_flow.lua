local controller_world = require("tests.controller_world")
local expect = require("tests.expect")

return {
    the_diagnostics_show_the_build_the_desktops_shown_and_the_numbers_of_the_profile = function()
        local world = controller_world.start_world()
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local printed, original_print = {}, print
        _G.print = function(text) -- luacheck: ignore 122
            table.insert(printed, text)
        end
        local is_printed, error_message =
            pcall(controller_world.find_menu_item(world, "Print diagnostics to the console").fn)
        _G.print = original_print -- luacheck: ignore 122
        if not is_printed then
            error(error_message, 0)
        end
        local lines = {}
        for line in table.concat(printed, "\n"):gmatch("[^\n]+") do
            lines[line] = true
        end
        expect.equal(lines["Hammerspoon 8cde946"], true)
        expect.equal(lines["  desktops of BUILTIN-UUID (built-in): 1=3 2=14 3=64, shown 1"], true)
        expect.equal(lines["profile 1 holds 3 desktops on built-in and shows desktop 1"], true)
        expect.equal(lines["profile 1 had the focus on built-in"], true)
        expect.equal(lines["windows out of reach: 1"], true)
    end,

    the_diagnostics_print_every_screen_desktop_number_and_window_of_two_screens = function()
        local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
        world.hotkeys["1"]()
        world.advance(controller_world.SETTLE_SECONDS)
        world.create_unseen_window("com.apple.Safari", "Reading list", 64)
        world.advance(controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS)
        local printed, original_print = {}, print
        _G.print = function(text) -- luacheck: ignore 122
            table.insert(printed, text)
        end
        local is_printed, error_message =
            pcall(controller_world.find_menu_item(world, "Print diagnostics to the console").fn)
        _G.print = original_print -- luacheck: ignore 122
        if not is_printed then
            error(error_message, 0)
        end
        local lines = {}
        for line in table.concat(printed, "\n"):gmatch("[^\n]+") do
            table.insert(lines, line)
        end
        expect.present(lines[3]:match("^running timers: %d+$"), "the line of the running timers")
        lines[3] = "running timers"
        expect.equal(lines, {
            "Hammerspoon 8cde946",
            "accessibility permission: true",
            "running timers",
            "monitor matching: by_count",
            "application pool: every application except none",
            "monitor configuration: built-in + 1 external",
            '  screen BUILTIN-UUID "Built-in Retina Display" built-in=true slot=built-in',
            '  screen DELL-UUID "DELL S2725DS" built-in=false slot=external 1',
            "  desktops of BUILTIN-UUID (built-in): 1=3 2=14 3=64, shown 1",
            "  desktops of DELL-UUID (external 1): 1=7 2=8 3=9 4=10, shown 1",
            "focused desktop: 3",
            "desktops kept per display: built-in 3, external 1 4",
            "active profile: 1",
            "profile 1 holds 3 desktops on built-in and shows desktop 1",
            "profile 1 holds 4 desktops on external 1 and shows desktop 1",
            "profile 1 had the focus on built-in",
            "application numbers of Profile 1:",
            "  app number 1: Microsoft Word com.microsoft.Word",
            "  app number 2: Safari com.apple.Safari",
            "windows out of reach: 1",
            '  window 41 com.apple.Safari "Inbox" desktop=8 out-of-sight=false in-filter=true'
                .. " recorded=1 in sight",
            '  window 42 com.microsoft.Word "Draft.docx" desktop=3 out-of-sight=false'
                .. " in-filter=true recorded=1 in sight",
            '  window 43 com.microsoft.Word "Report.docx" desktop=9 out-of-sight=false'
                .. " in-filter=true recorded=1 in sight",
        })
    end,
}
