local app_number_list_view = require("desktop_manager.core.app_number_list_view")
local expect = require("tests.expect")

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
        local selection = app_number_list_view.press(APPLICATIONS, nil, 1)
        expect.equal(selection, { number = 1, window_index = 2 })
        selection = app_number_list_view.press(APPLICATIONS, selection, 1)
        expect.equal(app_number_list_view.find_selected_window_id(APPLICATIONS, selection), 30)
        selection = app_number_list_view.press(APPLICATIONS, selection, 1)
        expect.equal(app_number_list_view.find_selected_window_id(APPLICATIONS, selection), 10)
    end,

    a_press_of_another_number_selects_that_application = function()
        local selection =
            app_number_list_view.press(APPLICATIONS, { number = 1, window_index = 1 }, 3)
        expect.equal(selection, { number = 3, window_index = 0 })
        expect.equal(app_number_list_view.find_selected_window_id(APPLICATIONS, selection), nil)
        expect.equal(app_number_list_view.press(APPLICATIONS, selection, 3), selection)
    end,

    a_free_number_leaves_the_selection = function()
        local selection = { number = 1, window_index = 1 }
        expect.equal(app_number_list_view.press(APPLICATIONS, selection, 7), selection)
        expect.equal(app_number_list_view.press(APPLICATIONS, nil, 7), nil)
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
        local lines =
            app_number_list_view.describe_lines(applications, { number = 2, window_index = 1 }, 12)
        expect.equal(lines, {
            {
                text = "2   Safari",
                is_application = true,
                is_selected = false,
                bundle_id = "com.apple.Safari",
            },
            {
                text = "Abcdefghij …",
                is_application = false,
                is_selected = true,
                bundle_id = "com.apple.Safari",
                window_id = 5,
            },
        })
    end,

    an_application_without_windows_is_selected_on_its_own_line = function()
        local lines =
            app_number_list_view.describe_lines(APPLICATIONS, { number = 3, window_index = 0 }, 40)
        expect.equal(lines[5], {
            text = "3   Microsoft Word",
            is_application = true,
            is_selected = true,
            bundle_id = "com.microsoft.Word",
        })
        expect.equal(lines[6].text, "no window, a new one opens")
        expect.equal(lines[4].text, "untitled window")
    end,

    a_hidden_application_without_listed_windows_is_noted_as_hidden = function()
        local hidden_word = {
            number = 3,
            bundle_id = "com.microsoft.Word",
            app_name = "Microsoft Word",
            windows = {},
            first_window_index = 0,
            is_hidden = true,
        }
        local lines = app_number_list_view.describe_lines({ hidden_word }, nil, 40)
        expect.equal(lines[2].text, "hidden, a press unhides it")
        local groups = app_number_list_view.describe_application_columns({ hidden_word }, nil)
        expect.equal(groups[1].columns[1].note, "hidden, a press unhides it")
        expect.equal(app_number_list_view.describe_note(APPLICATIONS[1]), nil)
        expect.equal(
            app_number_list_view.describe_note(APPLICATIONS[2]),
            "no window, a new one opens"
        )
    end,

    application_columns_hold_every_window_and_mark_the_selection = function()
        local groups = app_number_list_view.describe_application_columns(
            APPLICATIONS,
            { number = 1, window_index = 2 }
        )
        expect.equal(#groups, 1)
        expect.equal(groups[1].display_name, nil)
        local firefox, word = groups[1].columns[1], groups[1].columns[2]
        expect.equal(firefox.number, 1)
        expect.equal(#firefox.cells, 3)
        expect.equal(firefox.cells[2], { window_id = 20, title = "News", is_selected = true })
        expect.equal(firefox.cells[3].title, "untitled window")
        expect.equal(word.cells, {})
        expect.equal(word.is_selected, false)
    end,

    display_columns_group_the_windows_by_display = function()
        local applications = {
            {
                number = 1,
                bundle_id = "org.mozilla.firefox",
                app_name = "Firefox",
                windows = {
                    { window_id = 10, title = "Inbox", screen_uuid = "LG" },
                    { window_id = 20, title = "News", screen_uuid = "BUILTIN" },
                    { window_id = 30, title = "Lost", screen_uuid = nil },
                },
                first_window_index = 1,
            },
            {
                number = 2,
                bundle_id = "com.microsoft.VSCode",
                app_name = "Code",
                windows = { { window_id = 40, title = "Draft", screen_uuid = "LG" } },
                first_window_index = 1,
            },
            {
                number = 3,
                bundle_id = "com.microsoft.Word",
                app_name = "Microsoft Word",
                windows = {},
                first_window_index = 0,
            },
        }
        local groups = app_number_list_view.describe_display_columns(
            applications,
            { number = 3, window_index = 0 },
            {
                { screen_uuid = "BUILTIN", name = "Built-in Retina Display" },
                { screen_uuid = "LG", name = "LG TV SSCR2" },
            }
        )
        expect.equal(#groups, 3)
        expect.equal(groups[1].display_name, "Built-in Retina Display")
        expect.equal(#groups[1].columns, 1)
        expect.equal(groups[1].columns[1].cells[1].window_id, 20)
        expect.equal(groups[2].display_name, "LG TV SSCR2")
        expect.equal(groups[2].columns[1].number, 1)
        expect.equal(groups[2].columns[2].number, 2)
        expect.equal(groups[3].display_name, nil)
        expect.equal(groups[3].columns[1].cells[1].window_id, 30)
        expect.equal(groups[3].columns[2].number, 3)
        expect.equal(groups[3].columns[2].is_selected, true)
    end,

    a_scrolling_title_moves_left_and_starts_again_after_its_end = function()
        expect.equal(app_number_list_view.scroll_title("Abcdef", 0, 4), "Abcd")
        expect.equal(app_number_list_view.scroll_title("Abcdef", 3, 4), "def ")
        expect.equal(app_number_list_view.scroll_title("Abcdef", 9, 4), "  Ab")
        expect.equal(app_number_list_view.scroll_title("Abcdef", 10, 4), " Abc")
        expect.equal(app_number_list_view.scroll_title("Abcdef", 11, 4), "Abcd")
        expect.equal(app_number_list_view.scroll_title("Ünï—x", 1, 3), "nï—")
    end,
}
