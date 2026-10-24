local controller_world = require("tests.controller_world")
local expect = require("tests.expect")

---Starts the world with faulty settings and returns the message with which the start stops,
---after it checks that the message names the call of `profile_controller.start` in
---`controller_world.start_world` as the place of the fault.
---@param setting_changes table settings that replace the defaults
---@return string the message without its place
local function read_start_failure(setting_changes)
    local is_started, message = pcall(controller_world.start_world, setting_changes)
    expect.equal(is_started, false)
    local file, line_number, text = tostring(message):match("^(.-):(%d+): (.*)$")
    local start_world_source = debug.getinfo(controller_world.start_world, "S")
    expect.equal(file, start_world_source.short_src)
    expect.equal(tonumber(line_number) > start_world_source.linedefined, true)
    expect.equal(tonumber(line_number) < start_world_source.lastlinedefined, true)
    return text
end

return {
    an_unknown_way_to_match_windows_stops_the_start = function()
        expect.raises(function()
            controller_world.start_world({ match_windows_by = "guess" })
        end, 'the setting match_windows_by is "guess", which names no way to match windows')
    end,

    each_faulty_setting_stops_the_start_with_its_own_message = function()
        local faults = {
            {
                { preview_size = { w = 0, h = 0.1 } },
                "the setting preview_size must give w and h as fractions of the screen, above 0"
                    .. " and at most 1",
            },
            {
                { list_font_size = 0.2 },
                "the setting list_font_size is 0.2, and it must be a fraction of the height of the"
                    .. " screen, above 0 and at most 0.1",
            },
            {
                { title_overflow = "fade" },
                'the setting title_overflow is "fade", which names no way',
            },
            {
                { title_line_count = 1.5 },
                "the setting title_line_count is 1.5, and it must be a whole number of 1 or more",
            },
            {
                { list_sizing = "grow" },
                'the setting list_sizing is "grow", which names no sizing',
            },
            {
                { list_layout = "grid" },
                'the setting list_layout is "grid", which names no layout',
            },
            {
                { preview_blur = 0.5 },
                "the setting preview_blur is 0.5, and it must be a number of 1 or more",
            },
            {
                { preview_method = "thumbnails" },
                'the setting preview_method is "thumbnails", which names no method',
            },
            {
                { search_highlight_colors = { selected = { white = 1 } } },
                'the setting search_highlight_colors names "selected", which is none of selection,'
                    .. " hover, strong_match, medium_match, weak_match",
            },
            {
                { match_windows_by = "guess" },
                'the setting match_windows_by is "guess", which names no way to match windows',
            },
            {
                { missing_window_policy = "wait" },
                'the setting missing_window_policy is "wait", which names no policy',
            },
            {
                { unmatched_window_action = "drop" },
                'the setting unmatched_window_action is "drop", which names no action',
            },
            {
                { hidden_application_windows = "show_some" },
                'the setting hidden_application_windows is "show_some", which names no choice',
            },
            {
                { concealment_method = "close" },
                'the setting concealment_method is "close", which names no concealment method',
            },
        }
        for _, fault in ipairs(faults) do
            expect.equal(read_start_failure(fault[1]), fault[2])
        end
    end,

    of_two_faulty_settings_the_one_checked_first_stops_the_start = function()
        expect.equal(
            read_start_failure({ preview_blur = 0.5, concealment_method = "close" }),
            "the setting preview_blur is 0.5, and it must be a number of 1 or more"
        )
    end,

    an_unknown_action_for_an_unmatched_window_stops_the_start = function()
        local is_started = pcall(controller_world.start_world, { unmatched_window_action = "drop" })
        expect.equal(is_started, false)
    end,

    an_unknown_choice_for_hidden_application_windows_stops_the_start = function()
        expect.raises(function()
            controller_world.start_world({ hidden_application_windows = "show_some" })
        end, 'the setting hidden_application_windows is "show_some", which names no choice')
    end,

    an_old_value_of_missing_window_policy_starts_with_a_line_in_the_console = function()
        local world, controller =
            controller_world.start_world({ missing_window_policy = "open_new_window" })
        expect.equal(controller.settings.missing_window_policy, "match_id_alone")
        expect.equal(
            world.log_lines[1],
            'the setting missing_window_policy is "open_new_window", the old name of'
                .. ' "match_id_alone"'
        )
    end,
}
