local expect = require("tests.expect")
local window_search = require("desktop_manager.core.window_search")

local FIREFOX = "org.mozilla.firefox"
local MAIL = "com.apple.mail"

---@return SearchEntry[] the most recently focused first
local function build_entries()
    return {
        {
            window_id = 11,
            title = "GitHub - pull requests",
            bundle_id = FIREFOX,
            app_name = "Firefox",
        },
        { window_id = 21, title = "Inbox", bundle_id = MAIL, app_name = "Mail" },
        { window_id = 12, title = "Hammerspoon docs", bundle_id = FIREFOX, app_name = "Firefox" },
    }
end

---@param initial_window_id integer|nil
---@return WindowSearch
local function start(initial_window_id)
    return window_search.start(build_entries(), { [FIREFOX] = 1 }, initial_window_id)
end

---@param search WindowSearch
---@return string[] the bundle id of each application with its marks
local function describe_applications(search)
    local described = {}
    for _, application in ipairs(window_search.describe_view(search).applications) do
        table.insert(
            described,
            string.format(
                "%s %s%s%s%s",
                application.bundle_id,
                application.match_level or "-",
                application.is_faded and " faded" or "",
                application.is_hovered and " hovered" or "",
                application.is_chosen and " chosen" or ""
            )
        )
    end
    return described
end

return {
    without_words_every_window_shows_with_the_initial_one_selected = function()
        local search = start(21)
        expect.equal(search.shown, { 11, 21, 12 })
        expect.equal(window_search.find_selected_window_id(search), 21)
        local view = window_search.describe_view(search)
        expect.equal(view.applications[1].app_name, "Firefox")
        expect.equal(view.applications[1].number, 1)
        expect.equal(view.applications[2].number, nil)
        expect.equal(view.windows[2].is_selected, true)
        expect.equal(view.line.summary, "3 windows")
    end,

    tab_visits_the_windows_in_view = function()
        local search = window_search.select_next(start(21))
        expect.equal(window_search.find_selected_window_id(search), 12)
        search = window_search.select_next(search)
        expect.equal(window_search.find_selected_window_id(search), 11)
        search = window_search.select_previous(search)
        expect.equal(window_search.find_selected_window_id(search), 12)
    end,

    typing_shows_the_matches_from_the_best_down = function()
        local search = window_search.type_text(start(21), "p")
        expect.equal(search.shown, { 11, 12 })
        expect.equal(search.levels, { [11] = "strong", [12] = "weak" })
        expect.equal(window_search.find_selected_window_id(search), 11)
        expect.equal(describe_applications(search), { FIREFOX .. " strong", MAIL .. " - faded" })
        expect.equal(window_search.describe_view(search).line.summary, "2 of 3 windows match")
    end,

    the_name_of_the_application_and_the_title_both_count = function()
        expect.equal(window_search.type_text(start(nil), "fire docs").shown, { 12 })
        expect.equal(window_search.type_text(start(nil), "mail").shown, { 21 })
    end,

    hovering_over_an_application_shows_its_windows_until_the_mouse_leaves = function()
        local search = window_search.hover_application(start(11), MAIL)
        expect.equal(search.shown, { 21 })
        expect.equal(window_search.find_selected_window_id(search), 21)
        expect.equal(window_search.describe_view(search).line.summary, "1 window of Mail")
        expect.equal(describe_applications(search)[2], MAIL .. " - hovered")
        search = window_search.hover_application(search, nil)
        expect.equal(search.shown, { 11, 21, 12 })
        expect.equal(window_search.find_selected_window_id(search), 21)
    end,

    a_chosen_application_stays_while_the_mouse_hovers_over_another = function()
        local search = window_search.choose_application(start(21), FIREFOX)
        search = window_search.hover_application(search, MAIL)
        expect.equal(search.shown, { 11, 12 })
        expect.equal(
            window_search.describe_view(search).line.summary,
            "2 windows of Firefox, chosen"
        )
        search = window_search.choose_application(search, FIREFOX)
        expect.equal(search.shown, { 21 })
    end,

    typing_drops_the_applications_of_the_mouse = function()
        local search = window_search.choose_application(start(21), FIREFOX)
        search = window_search.hover_application(search, MAIL)
        search = window_search.type_text(search, "inbox")
        expect.equal(search.chosen_bundle_id, nil)
        expect.equal(search.hovered_bundle_id, nil)
        expect.equal(search.shown, { 21 })
    end,

    the_mouse_selects_a_window_in_view_alone = function()
        local search = window_search.select_window(start(21), 12)
        expect.equal(window_search.find_selected_window_id(search), 12)
        search = window_search.type_text(search, "inbox")
        expect.equal(window_search.select_window(search, 12), search)
    end,

    new_windows_keep_the_text_and_the_selection = function()
        local search = window_search.select_next(window_search.type_text(start(21), "p"))
        local entries = build_entries()
        table.insert(
            entries,
            { window_id = 31, title = "Pasta", bundle_id = "com.apple.Notes", app_name = "Notes" }
        )
        search = window_search.with_entries(search, entries)
        expect.equal(search.text, "p")
        expect.equal(search.shown, { 11, 31, 12 })
        expect.equal(window_search.find_selected_window_id(search), 12)
        expect.equal(#window_search.describe_view(search).applications, 3)
    end,

    deleting_the_text_brings_back_the_initial_window = function()
        local search = window_search.type_text(start(12), "pé")
        search = window_search.delete_last_character(search)
        expect.equal(search.text, "p")
        search = window_search.delete_last_character(search)
        expect.equal(search.text, "")
        expect.equal(search.levels, {})
        expect.equal(window_search.find_selected_window_id(search), 12)
        search = window_search.clear_text(window_search.type_text(search, "inbox"))
        expect.equal(window_search.find_selected_window_id(search), 12)
    end,

    a_search_without_a_match_selects_nothing = function()
        local search = window_search.type_text(start(12), "zz")
        expect.equal(window_search.find_selected_window_id(search), nil)
        expect.equal(window_search.find_selected_window_id(window_search.select_next(search)), nil)
        expect.equal(window_search.describe_view(search).line.summary, "no window matches")
        expect.equal(
            window_search.describe_view(window_search.start({}, {}, nil)).line.summary,
            "no window is open"
        )
    end,

    the_arrows_move_in_the_grid_and_stop_at_its_edges = function()
        local entries = {}
        for window_id = 1, 5 do
            table.insert(entries, {
                window_id = window_id,
                title = "Note " .. window_id,
                bundle_id = "com.apple.Notes",
                app_name = "Notes",
            })
        end
        local search = window_search.start(entries, {}, 1)
        local function move(direction)
            search = window_search.move_in_grid(search, 3, direction)
            return window_search.find_selected_window_id(search)
        end
        expect.equal(move(window_search.LEFT), 1)
        expect.equal(move(window_search.UP), 1)
        expect.equal(move(window_search.RIGHT), 2)
        expect.equal(move(window_search.RIGHT), 3)
        expect.equal(move(window_search.RIGHT), 3)
        expect.equal(move(window_search.DOWN), 5)
        expect.equal(move(window_search.DOWN), 5)
        expect.equal(move(window_search.RIGHT), 5)
        expect.equal(move(window_search.LEFT), 4)
        expect.equal(move(window_search.UP), 1)
        expect.equal(move(window_search.DOWN), 4)
        expect.equal(pcall(window_search.move_in_grid, search, 3, "inward"), false)
    end,
}
