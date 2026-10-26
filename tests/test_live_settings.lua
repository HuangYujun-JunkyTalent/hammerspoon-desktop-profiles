local default_settings = require("desktop_manager.default_settings")
local expect = require("tests.expect")
local list_layout = require("desktop_manager.core.list_layout")
local live_settings = require("desktop_manager.core.live_settings")
local profile_state = require("desktop_manager.core.profile_state")
local settings_check = require("desktop_manager.core.settings_check")
local unmatched_window_action = require("desktop_manager.core.unmatched_window_action")

---@return Settings the checked default settings
local function check_defaults()
    local checked = settings_check.check(default_settings.create("/fake/state.json"))
    return checked --[[@as Settings]]
end

return {
    each_entry_names_a_setting_of_the_file_or_the_monitor_matching = function()
        local defaults = check_defaults()
        for _, entry in ipairs(live_settings.ENTRIES) do
            if entry.is_kept_in_state then
                expect.equal(entry.name, "monitor_matching")
            elseif defaults[entry.name] == nil then
                error("the window changes " .. entry.name .. ", which the file does not set")
            end
            expect.equal(live_settings.find(entry.name), entry)
        end
    end,

    the_default_of_each_entry_is_a_value_that_the_window_offers = function()
        local defaults = check_defaults()
        for _, entry in ipairs(live_settings.ENTRIES) do
            local default = entry.is_kept_in_state and defaults.initial_monitor_matching
                or defaults[entry.name]
            expect.equal(live_settings.read_value(entry, default), default)
        end
    end,

    a_value_is_read_into_the_shape_of_its_setting_or_refused = function()
        local action = live_settings.find("unmatched_window_action") --[[@as LiveSetting]]
        expect.equal(live_settings.read_value(action, "forget"), "forget")
        expect.equal(live_settings.read_value(action, "drop"), nil)
        local line_count = live_settings.find("title_line_count") --[[@as LiveSetting]]
        expect.equal(math.type(live_settings.read_value(line_count, 3.0)), "integer")
        expect.equal(live_settings.read_value(line_count, 2.5), nil)
        expect.equal(live_settings.read_value(line_count, 0), nil)
        local size = live_settings.find("preview_size") --[[@as LiveSetting]]
        expect.equal(
            live_settings.read_value(size, { w = 0.2, h = 0.15, extra = 1 }),
            { w = 0.2, h = 0.15 }
        )
        expect.equal(live_settings.read_value(size, { w = 0.2 }), nil)
    end,

    the_overrides_replace_the_values_of_the_file_and_leave_the_others = function()
        local base = check_defaults()
        local settings, kept, lines = live_settings.apply(base, {
            unmatched_window_action = unmatched_window_action.FORGET,
            list_layout = list_layout.ROWS,
        })
        expect.equal(settings.unmatched_window_action, unmatched_window_action.FORGET)
        expect.equal(settings.list_layout, list_layout.ROWS)
        expect.equal(settings.match_windows_by, base.match_windows_by)
        expect.equal(kept, { unmatched_window_action = "forget", list_layout = "rows" })
        expect.equal(lines, {})
        expect.equal(base.unmatched_window_action, unmatched_window_action.OPEN_NEW_WINDOW)
    end,

    an_override_that_the_checks_refuse_is_left_out_with_a_line = function()
        local _, kept, lines = live_settings.apply(check_defaults(), { list_layout = "grid" })
        expect.equal(kept, {})
        expect.equal(lines, {
            "the saved choice of the window Settings is left out:"
                .. ' the setting list_layout is "grid", which names no layout',
        })
    end,

    the_state_keeps_the_overrides_that_the_window_offers = function()
        local state, message = profile_state.decode({
            format_version = profile_state.FORMAT_VERSION,
            monitor_matching = "by_count",
            setting_overrides = {
                unmatched_window_action = "forget",
                list_layout = "grid",
                monitor_matching = "by_identity",
                profile_count = 3,
            },
        })
        expect.equal(message, nil)
        expect.equal(
            (state --[[@as State]]).setting_overrides,
            { unmatched_window_action = "forget" }
        )
        expect.equal(profile_state.new_state("by_count").setting_overrides, {})
    end,
}
