local expect = require("tests.expect")
local switch_list = require("desktop_manager.core.switch_list")

local APPLICATIONS = {
    {
        number = 1,
        bundle_id = "org.mozilla.firefox",
        app_name = "Firefox",
        windows = {
            { window_id = 10, title = "Inbox" },
            { window_id = 20, title = "News" },
            { window_id = 30, title = "" },
        },
        first_window_index = 2,
    },
    {
        number = 3,
        bundle_id = "com.microsoft.Word",
        app_name = "Microsoft Word",
        windows = {},
        first_window_index = 0,
    },
}

return {
    the_first_press_selects_the_first_window_and_the_next_press_the_next_one = function()
        local selection = switch_list.press(APPLICATIONS, nil, 1)
        expect.equal(selection, { number = 1, window_index = 2 })
        selection = switch_list.press(APPLICATIONS, selection, 1)
        expect.equal(switch_list.find_selected_window_id(APPLICATIONS, selection), 30)
        selection = switch_list.press(APPLICATIONS, selection, 1)
        expect.equal(switch_list.find_selected_window_id(APPLICATIONS, selection), 10)
    end,

    a_press_of_another_number_selects_that_application = function()
        local selection = switch_list.press(APPLICATIONS, { number = 1, window_index = 1 }, 3)
        expect.equal(selection, { number = 3, window_index = 0 })
        expect.equal(switch_list.find_selected_window_id(APPLICATIONS, selection), nil)
        expect.equal(switch_list.press(APPLICATIONS, selection, 3), selection)
    end,

    a_free_number_leaves_the_selection = function()
        local selection = { number = 1, window_index = 1 }
        expect.equal(switch_list.press(APPLICATIONS, selection, 7), selection)
        expect.equal(switch_list.press(APPLICATIONS, nil, 7), nil)
    end,

    the_lines_mark_the_selected_window_and_shorten_long_titles = function()
        local applications = {
            {
                number = 2,
                bundle_id = "com.apple.Safari",
                app_name = "Safari",
                windows = { { window_id = 5, title = "Abcdefghij — Ünïcode" } },
                first_window_index = 1,
            },
        }
        local lines = switch_list.describe_lines(applications, { number = 2, window_index = 1 }, 12)
        expect.equal(lines, {
            { text = "2   Safari", is_application = true, is_selected = false },
            { text = "      Abcdefghij …", is_application = false, is_selected = true },
        })
    end,

    an_application_without_windows_is_selected_on_its_own_line = function()
        local lines = switch_list.describe_lines(APPLICATIONS, { number = 3, window_index = 0 }, 40)
        expect.equal(
            lines[5],
            { text = "3   Microsoft Word", is_application = true, is_selected = true }
        )
        expect.equal(lines[6].text, "      no window, a new one opens")
        expect.equal(lines[4].text, "      untitled window")
    end,
}
