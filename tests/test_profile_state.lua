local expect = require("tests.expect")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local profile_state = require("desktop_manager.core.profile_state")

local ARRANGEMENT = {
    monitor_configuration_key = "built-in",
    monitors = { { slot_key = "built-in", desktop_count = 2 } },
    focus = { slot_key = "built-in", desktop_number = 1 },
    windows = {
        {
            window_id = 41,
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            title = "Inbox",
            slot_key = "built-in",
            desktop_number = 2,
            unit_frame = { x = 0, y = 0, w = 0.5, h = 1 },
            is_out_of_sight = false,
        },
    },
}

return {
    a_new_profile_has_a_numbered_name = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        expect.equal(profile_state.profile_or_default(state, 4).name, "Profile 4")
    end,

    rename_trims_and_keeps_the_original_state = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        local renamed = profile_state.rename_profile(state, 2, "  Writing  ")
        expect.equal(profile_state.profile_or_default(renamed, 2).name, "Writing")
        expect.equal(state.profiles["2"], nil)
    end,

    rename_rejects_a_blank_name = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        expect.raises(function()
            profile_state.rename_profile(state, 2, "   ")
        end, "needs a visible character")
    end,

    the_index_lists_the_windows_that_any_arrangement_records = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        state = profile_state.with_arrangement(state, 3, ARRANGEMENT)
        state = profile_state.with_arrangement(state, 4, {
            monitor_configuration_key = "built-in + 1 external",
            monitors = {},
            focus = nil,
            windows = {
                {
                    window_id = 77,
                    bundle_id = "com.apple.Notes",
                    app_name = "Notes",
                    title = "Shopping",
                    is_out_of_sight = true,
                },
            },
        })
        local recorded = profile_state.index_recorded_windows(state)
        expect.equal(recorded[77], { ["com.apple.Notes"] = true })
        expect.equal(recorded[78], nil)
    end,

    a_rename_gives_the_records_of_every_profile_the_new_window_id = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        state = profile_state.with_arrangement(state, 3, ARRANGEMENT)
        state = profile_state.with_arrangement(state, 4, ARRANGEMENT)
        local renamed = profile_state.rename_windows(state, {
            { bundle_id = "com.apple.Safari", old_window_id = 41, new_window_id = 90 },
            { bundle_id = "com.apple.Notes", old_window_id = 41, new_window_id = 91 },
        })
        expect.equal(
            profile_state.find_arrangement(renamed, 3, "built-in").windows[1].window_id,
            90
        )
        expect.equal(
            profile_state.find_arrangement(renamed, 4, "built-in").windows[1].window_id,
            90
        )
        expect.equal(profile_state.find_arrangement(state, 3, "built-in").windows[1].window_id, 41)
        expect.equal(#profile_state.list_all_records(renamed), 2)
    end,

    an_arrangement_is_kept_per_monitor_configuration = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        state = profile_state.with_arrangement(state, 3, ARRANGEMENT)
        expect.equal(profile_state.find_arrangement(state, 3, "built-in"), ARRANGEMENT)
        expect.equal(profile_state.find_arrangement(state, 3, "built-in + 1 external"), nil)
    end,

    profile_numbers_must_be_positive_integers = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        expect.raises(function()
            profile_state.profile_or_default(state, 0)
        end, "positive integer, and 0 was given")
    end,

    decode_turns_whole_floats_into_integers = function()
        local raw = {
            format_version = 1.0,
            monitor_matching = "by_identity",
            active_profile_number = 3.0,
            profiles = {
                ["3"] = {
                    number = 3.0,
                    name = "Research",
                    arrangements = {
                        ["built-in"] = {
                            monitor_configuration_key = "built-in",
                            monitors = {},
                            windows = {
                                {
                                    window_id = 41.0,
                                    bundle_id = "com.apple.Safari",
                                    is_minimized = true,
                                },
                            },
                        },
                    },
                },
            },
        }
        local state = profile_state.decode(raw)
        expect.equal(state.active_profile_number, 3)
        expect.equal(math.type(state.active_profile_number), "integer")
        local record = profile_state.find_arrangement(state, 3, "built-in").windows[1]
        expect.equal(math.type(record.window_id), "integer")
        expect.equal(record.is_out_of_sight, true)
        expect.equal(state.monitor_matching, "by_identity")
    end,

    decode_round_trips_an_arrangement_and_app_numbers = function()
        local state = profile_state.with_arrangement(
            profile_state.new_state(monitor_matching.BY_COUNT),
            1,
            ARRANGEMENT
        )
        state = profile_state.with_app_numbers(state, 1, {
            {
                number = 3,
                bundle_id = "com.apple.Safari",
                app_name = "Safari",
                is_chosen_by_user = true,
            },
        })
        local decoded = profile_state.decode(state)
        expect.equal(decoded, state)
    end,

    decode_rejects_another_format_version = function()
        local state, message =
            profile_state.decode({ format_version = 2, monitor_matching = "by_count" })
        expect.equal(state, nil)
        expect.equal(message, "the saved state has format version 2, and this version reads 1")
    end,
}
