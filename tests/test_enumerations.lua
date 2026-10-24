local concealment_method = require("desktop_manager.core.concealment_method")
local expect = require("tests.expect")
local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")
local list_layout = require("desktop_manager.core.list_layout")
local list_sizing = require("desktop_manager.core.list_sizing")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local preview_method = require("desktop_manager.core.preview_method")
local title_overflow = require("desktop_manager.core.title_overflow")
local unmatched_window_action = require("desktop_manager.core.unmatched_window_action")

---@class EnumerationCase
---@field name string the name of the module
---@field values table the module
---@field constants table<string, string> the constants that the module must hold, with their values

---@type EnumerationCase[]
local CASES = {
    {
        name = "concealment_method",
        values = concealment_method,
        constants = {
            MINIMIZE_WINDOWS = "minimize_windows",
            HIDE_APPLICATIONS = "hide_applications",
        },
    },
    {
        name = "hidden_application_windows",
        values = hidden_application_windows,
        constants = {
            LEAVE_OUT = "leave_out",
            LIST_WHERE_FOUND = "list_where_found",
            LIST_ALL = "list_all",
        },
    },
    {
        name = "list_layout",
        values = list_layout,
        constants = {
            ROWS = "rows",
            COLUMNS = "columns",
            COLUMNS_PER_DISPLAY = "columns_per_display",
        },
    },
    {
        name = "list_sizing",
        values = list_sizing,
        constants = { FILL_SCREEN = "fill_screen", FIXED = "fixed" },
    },
    {
        name = "match_windows_by",
        values = match_windows_by,
        constants = { TITLE = "title", ID = "id" },
    },
    {
        name = "missing_window_policy",
        values = missing_window_policy,
        constants = {
            OPEN_NEW_WINDOW = "open_new_window",
            MATCH_TITLE_OR_OPEN_NEW_WINDOW = "match_title_or_open_new_window",
        },
    },
    {
        name = "preview_method",
        values = preview_method,
        constants = { APP_ICONS = "app_icons", BLURRED_SNAPSHOTS = "blurred_snapshots" },
    },
    {
        name = "title_overflow",
        values = title_overflow,
        constants = { TRUNCATE = "truncate", WRAP = "wrap", SCROLL = "scroll" },
    },
    {
        name = "unmatched_window_action",
        values = unmatched_window_action,
        constants = { OPEN_NEW_WINDOW = "open_new_window", FORGET = "forget" },
    },
}

return {
    each_closed_set_accepts_exactly_the_values_of_its_constants = function()
        for _, case in ipairs(CASES) do
            local module_constants = {}
            for name, value in pairs(case.values) do
                if type(value) == "string" then
                    module_constants[name] = value
                end
            end
            expect.equal({ case.name, module_constants }, { case.name, case.constants })
            for _, value in pairs(case.constants) do
                expect.equal({ case.name, value, case.values.is_valid(value) }, {
                    case.name,
                    value,
                    true,
                })
            end
            expect.equal({ case.name, case.values.is_valid(nil) }, { case.name, false })
            for _, value in ipairs({ "unknown", "", 1, case.values.is_valid, {} }) do
                expect.equal({ case.name, value, case.values.is_valid(value) }, {
                    case.name,
                    value,
                    false,
                })
            end
        end
    end,
}
