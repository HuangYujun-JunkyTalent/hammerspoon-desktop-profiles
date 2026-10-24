local expect = require("tests.expect")
local shortcut_window_model = require("keyboard_shortcuts.core.shortcut_window_model")

local SEARCH_SHORTCUT = { modifiers = { "ctrl", "alt", "cmd" }, key = "space" }
local PROFILE_SHORTCUT = { modifiers = { "cmd", "alt", "shift" }, key = "1" }
local SPOTLIGHT = { id = 64, name = "Show Spotlight search", key_code = 49, flags = 1048576 }

---@param rows ShortcutRow[]
---@return table a center whose `list_rows` returns the rows
local function center_of_rows(rows)
    return {
        list_rows = function()
            return rows
        end,
    }
end

---@param shortcut Shortcut
---@return MacosShortcut|nil Spotlight for the search shortcut, and nothing for any other shortcut
local function find_spotlight_conflict(shortcut)
    return shortcut == SEARCH_SHORTCUT and SPOTLIGHT or nil
end

return {
    the_rows_stand_in_groups_in_the_order_of_their_first_row = function()
        local center = center_of_rows({
            {
                id = "profiles.toggle.1",
                group = "Profiles",
                title = "Activate profile 1",
                shortcut = PROFILE_SHORTCUT,
                default = PROFILE_SHORTCUT,
                is_default = true,
            },
            {
                id = "window_search.toggle",
                group = "Window search",
                title = "Show the search",
                shortcut = SEARCH_SHORTCUT,
                default = SEARCH_SHORTCUT,
                is_default = true,
            },
            {
                id = "profiles.deactivate",
                group = "Profiles",
                title = "Deactivate the active profile",
                shortcut = nil,
                default = nil,
                is_default = false,
            },
        })
        local model = shortcut_window_model.build_model(center, {}, nil, find_spotlight_conflict)
        expect.equal(#model.groups, 2)
        expect.equal(model.groups[1].name, "Profiles")
        expect.equal(model.groups[1].rows[1].id, "profiles.toggle.1")
        expect.equal(model.groups[1].rows[2].id, "profiles.deactivate")
        expect.equal(model.groups[2].name, "Window search")
        expect.equal(model.groups[2].rows[1].id, "window_search.toggle")
    end,

    a_row_gives_the_text_of_its_default_and_the_macos_shortcut_it_collides_with = function()
        local center = center_of_rows({
            {
                id = "window_search.toggle",
                group = "Window search",
                title = "Show the search",
                shortcut = SEARCH_SHORTCUT,
                default = SEARCH_SHORTCUT,
                is_default = true,
            },
            {
                id = "profiles.deactivate",
                group = "Profiles",
                title = "Deactivate the active profile",
                shortcut = nil,
                default = nil,
                is_default = false,
            },
        })
        local model = shortcut_window_model.build_model(center, {}, nil, find_spotlight_conflict)
        local search_row = model.groups[1].rows[1]
        expect.equal(search_row.default_text, "Control-Option-Command-Space")
        expect.equal(search_row.macos_conflict, { id = 64, name = "Show Spotlight search" })
        local deactivate_row = model.groups[2].rows[1]
        expect.equal(deactivate_row.default_text, "none")
        expect.equal(deactivate_row.macos_conflict, nil)
        expect.equal(deactivate_row.is_default, false)
    end,

    a_pending_shortcut_shows_its_text_its_holder_and_the_name_of_the_macos_shortcut = function()
        local holder = { id = "profiles.toggle.1", title = "Activate profile 1" }
        local problems = { "the shortcuts could not be written to /fake/keyboard-shortcuts.json" }
        local model = shortcut_window_model.build_model(center_of_rows({}), problems, {
            id = "window_search.toggle",
            shortcut = PROFILE_SHORTCUT,
            holder = holder,
            macos = SPOTLIGHT,
        }, find_spotlight_conflict)
        expect.equal(model.groups, {})
        expect.equal(model.problems, problems)
        expect.equal(model.pending, {
            id = "window_search.toggle",
            shortcut = PROFILE_SHORTCUT,
            text = "Option-Shift-Command-1",
            holder = holder,
            macos = { id = 64, name = "Show Spotlight search" },
        })
    end,
}
