local app_numbers = require("desktop_manager.core.app_numbers")
local expect = require("tests.expect")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }
local EXTERNAL_FRAME = { x = 1440, y = 0, w = 1920, h = 1080 }

local CONFIGURATION = monitor_configuration.describe({
    {
        uuid = "BUILTIN-UUID",
        name = "Built-in Retina Display",
        is_builtin = true,
        frame = BUILTIN_FRAME,
    },
    { uuid = "EXTERNAL-UUID", name = "LG TV SSCR2", is_builtin = false, frame = EXTERNAL_FRAME },
}, monitor_matching.BY_COUNT)

---@param bundle_id string
---@param slot_key string
---@param desktop_number integer
---@param left_edge number
---@return WindowRecord
local function record_of(bundle_id, slot_key, desktop_number, left_edge)
    return {
        window_id = #bundle_id + desktop_number,
        bundle_id = bundle_id,
        app_name = bundle_id:match("[^.]+$"),
        title = bundle_id,
        slot_key = slot_key,
        desktop_number = desktop_number,
        unit_frame = { x = left_edge, y = 0, w = 0.5, h = 1 },
        is_out_of_sight = false,
    }
end

---@param records WindowRecord[]
---@return Arrangement
local function arrangement_of(records)
    return {
        monitor_configuration_key = CONFIGURATION.key,
        monitors = {},
        windows = records,
    }
end

---@param entries AppNumber[]
---@return table<integer, string> the bundle id of each number
local function bundles_by_number(entries)
    local bundles = {}
    for _, entry in ipairs(entries) do
        bundles[entry.number] = entry.bundle_id
    end
    return bundles
end

return {
    defaults_follow_screens_then_desktops_then_left_edges = function()
        local hidden = record_of("com.apple.Notes", "built-in", 1, 0)
        hidden.is_out_of_sight = true
        local entries = app_numbers.update_defaults(
            {},
            arrangement_of({
                record_of("org.mozilla.firefox", "external 1", 1, 0),
                record_of("com.tinyspeck.slackmacgap", "built-in", 2, 0),
                record_of("com.apple.iCal", "built-in", 1, 0.5),
                record_of("com.microsoft.VSCode", "built-in", 1, 0),
                record_of("com.microsoft.VSCode", "external 1", 2, 0),
                hidden,
            }),
            CONFIGURATION,
            9
        )
        expect.equal(bundles_by_number(entries), {
            [1] = "com.microsoft.VSCode",
            [2] = "com.apple.iCal",
            [3] = "com.tinyspeck.slackmacgap",
            [4] = "org.mozilla.firefox",
        })
    end,

    a_default_number_stays_while_its_application_stays = function()
        local before = app_numbers.update_defaults(
            {},
            arrangement_of({
                record_of("com.microsoft.VSCode", "built-in", 1, 0),
                record_of("com.apple.iCal", "built-in", 1, 0.5),
            }),
            CONFIGURATION,
            9
        )
        local after = app_numbers.update_defaults(
            before,
            arrangement_of({
                record_of("com.apple.iCal", "built-in", 1, 0),
                record_of("org.mozilla.firefox", "built-in", 1, 0.2),
            }),
            CONFIGURATION,
            9
        )
        expect.equal(bundles_by_number(after), {
            [1] = "org.mozilla.firefox",
            [2] = "com.apple.iCal",
        })
    end,

    a_default_number_stays_while_the_windows_of_its_application_are_out_of_sight = function()
        local before = app_numbers.update_defaults(
            {},
            arrangement_of({
                record_of("com.microsoft.VSCode", "built-in", 1, 0),
            }),
            CONFIGURATION,
            9
        )
        local minimized = record_of("com.microsoft.VSCode", "built-in", 1, 0)
        minimized.is_out_of_sight = true
        local after =
            app_numbers.update_defaults(before, arrangement_of({ minimized }), CONFIGURATION, 9)
        expect.equal(bundles_by_number(after), { [1] = "com.microsoft.VSCode" })
        local hidden_elsewhere = record_of("com.apple.Notes", "built-in", 1, 0)
        hidden_elsewhere.is_out_of_sight = true
        local unnumbered =
            app_numbers.update_defaults({}, arrangement_of({ hidden_elsewhere }), CONFIGURATION, 9)
        expect.equal(unnumbered, {})
    end,

    a_number_chosen_by_the_user_stays_and_moves_the_default = function()
        local chosen = app_numbers.choose({}, 1, "com.apple.Music", "Music")
        local entries = app_numbers.update_defaults(
            chosen,
            arrangement_of({
                record_of("com.microsoft.VSCode", "built-in", 1, 0),
            }),
            CONFIGURATION,
            9
        )
        expect.equal(bundles_by_number(entries), {
            [1] = "com.apple.Music",
            [2] = "com.microsoft.VSCode",
        })
        expect.equal(app_numbers.find_by_number(entries, 1).is_chosen_by_user, true)
    end,

    choosing_takes_the_number_from_its_holder_and_the_application_from_its_number = function()
        local entries = app_numbers.update_defaults(
            {},
            arrangement_of({
                record_of("com.microsoft.VSCode", "built-in", 1, 0),
                record_of("com.apple.iCal", "built-in", 1, 0.5),
            }),
            CONFIGURATION,
            9
        )
        local chosen = app_numbers.choose(entries, 1, "com.apple.iCal", "iCal")
        expect.equal(bundles_by_number(chosen), { [1] = "com.apple.iCal" })
        local released = app_numbers.release(chosen, 1)
        expect.equal(released, {})
    end,

    defaults_stop_at_the_count_of_numbers = function()
        local entries = app_numbers.update_defaults(
            {},
            arrangement_of({
                record_of("com.a.One", "built-in", 1, 0),
                record_of("com.b.Two", "built-in", 1, 0.1),
                record_of("com.c.Three", "built-in", 1, 0.2),
            }),
            CONFIGURATION,
            2
        )
        expect.equal(#entries, 2)
    end,

    the_next_window_follows_the_order_of_the_ids = function()
        expect.equal(app_numbers.find_next_window_id({ 30, 10, 20 }, 10), 20)
        expect.equal(app_numbers.find_next_window_id({ 30, 10, 20 }, 30), 10)
        expect.equal(app_numbers.find_next_window_id({ 30, 10, 20 }, nil), 10)
        expect.equal(app_numbers.find_next_window_id({}, nil), nil)
    end,

    the_first_press_selects_the_window_after_the_focused_one_while_in_front = function()
        expect.equal(app_numbers.find_first_selection_index({ 10, 20, 30 }, 30, 20), 3)
        expect.equal(app_numbers.find_first_selection_index({ 10, 20, 30 }, 30, 30), 1)
        expect.equal(app_numbers.find_first_selection_index({ 10 }, 10, 10), 1)
    end,

    the_first_press_selects_the_window_that_had_the_focus_last_otherwise = function()
        expect.equal(app_numbers.find_first_selection_index({ 10, 20, 30 }, 20, nil), 2)
        expect.equal(app_numbers.find_first_selection_index({ 10, 20, 30 }, nil, nil), 0)
        expect.equal(app_numbers.find_first_selection_index({}, nil, nil), 0)
    end,
}
