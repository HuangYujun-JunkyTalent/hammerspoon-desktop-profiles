local app_pool = require("desktop_manager.core.app_pool")
local expect = require("tests.expect")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local profile_state = require("desktop_manager.core.profile_state")

local ARRANGEMENT = {
    monitor_configuration_key = "built-in",
    monitors = { { slot_key = "built-in", desktop_count = 2, shown_desktop_number = 1 } },
    focused_slot_key = "built-in",
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

    profile_numbers_must_be_whole_numbers_of_0_or_more = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        expect.raises(function()
            profile_state.profile_or_default(state, -1)
        end, "0 or more, and %-1 was given")
    end,

    profile_0_holds_app_numbers_and_neither_records_windows_nor_activates = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        state = profile_state.with_app_numbers(state, profile_state.NO_PROFILE_NUMBER, {
            {
                number = 2,
                bundle_id = "com.apple.Safari",
                app_name = "Safari",
                is_chosen_by_user = true,
            },
        })
        expect.equal(profile_state.profile_or_default(state, 0).app_numbers[1].number, 2)
        expect.equal(profile_state.profile_or_default(state, 0).name, "Profile 0")
        expect.raises(function()
            profile_state.with_arrangement(state, 0, ARRANGEMENT)
        end, "profile 0 records no windows")
        expect.raises(function()
            profile_state.with_active_profile_number(state, 0)
        end, "cannot be activated")
    end,

    the_numbering_profile_is_the_active_profile_or_profile_0 = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        expect.equal(profile_state.find_numbering_profile_number(state), 0)
        state = profile_state.with_active_profile_number(state, 4)
        expect.equal(profile_state.find_numbering_profile_number(state), 4)
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

    decode_round_trips_the_app_pool_and_reads_the_list_of_an_older_state = function()
        local pool = app_pool.with_listed(app_pool.new(), "org.mozilla.firefox", "Firefox", true)
        local state =
            profile_state.with_app_pool(profile_state.new_state(monitor_matching.BY_COUNT), pool)
        expect.equal(profile_state.decode(state), state)
        local older = profile_state.new_state(monitor_matching.BY_COUNT)
        older.app_pool = nil
        older.managed_applications = { { bundle_id = "org.mozilla.firefox", app_name = "Firefox" } }
        expect.equal(profile_state.decode(older).app_pool.mode, app_pool.MANAGE_LISTED)
    end,

    decode_round_trips_the_desktop_counts_and_reads_a_state_without_them = function()
        local state =
            profile_state.with_desktop_counts(profile_state.new_state(monitor_matching.BY_COUNT), {
                kept = { ["built-in"] = 3, ["external 1"] = 4 },
                last_reading = {
                    displays_key = "BUILTIN-UUID;DELL-UUID",
                    counts = { ["built-in"] = 5, ["external 1"] = 4 },
                },
            })
        expect.equal(profile_state.decode(state), state)
        local older = profile_state.new_state(monitor_matching.BY_COUNT)
        older.desktop_counts = nil
        expect.equal(profile_state.decode(older).desktop_counts, { kept = {}, last_reading = nil })
        older.desktop_counts = { kept = { ["built-in"] = 0, [""] = 2.0 }, last_reading = 7 }
        expect.equal(
            profile_state.decode(older).desktop_counts,
            { kept = { [""] = 2 }, last_reading = nil }
        )
    end,

    clearing_a_profile_keeps_its_name_and_numbers = function()
        local state = profile_state.with_arrangement(
            profile_state.rename_profile(
                profile_state.new_state(monitor_matching.BY_COUNT),
                1,
                "Writing"
            ),
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
        expect.equal(profile_state.has_arrangements(state, 1), true)
        local cleared = profile_state.clear_arrangements(state, 1)
        expect.equal(profile_state.has_arrangements(cleared, 1), false)
        expect.equal(profile_state.profile_or_default(cleared, 1).name, "Writing")
        expect.equal(
            profile_state.profile_or_default(cleared, 1).app_numbers,
            profile_state.profile_or_default(state, 1).app_numbers
        )
        expect.equal(profile_state.has_arrangements(state, 1), true)
    end,

    decode_keeps_the_numbers_of_profile_0_and_drops_its_arrangements = function()
        local state =
            profile_state.with_app_numbers(profile_state.new_state(monitor_matching.BY_COUNT), 0, {
                {
                    number = 1,
                    bundle_id = "com.microsoft.Word",
                    app_name = "Microsoft Word",
                    is_chosen_by_user = false,
                },
            })
        state.profiles["0"].arrangements["built-in"] = ARRANGEMENT
        local decoded = profile_state.decode(state)
        expect.equal(decoded.profiles["0"].app_numbers, state.profiles["0"].app_numbers)
        expect.equal(decoded.profiles["0"].arrangements, {})
    end,

    decode_rejects_another_format_version = function()
        local state, message =
            profile_state.decode({ format_version = 3, monitor_matching = "by_count" })
        expect.equal(state, nil)
        expect.equal(message, "the saved state has format version 3, and this version reads 1 to 2")
    end,

    a_saved_focus_becomes_the_desktop_shown_of_its_screen = function()
        local state = profile_state.decode({
            format_version = 1,
            monitor_matching = "by_count",
            profiles = {
                ["1"] = {
                    number = 1,
                    arrangements = {
                        ["built-in + 1 external"] = {
                            monitor_configuration_key = "built-in + 1 external",
                            monitors = {
                                { slot_key = "built-in", desktop_count = 3 },
                                { slot_key = "external 1", desktop_count = 2 },
                            },
                            focus = { slot_key = "external 1", desktop_number = 2.0 },
                            windows = {},
                        },
                    },
                },
            },
        })
        local arrangement = profile_state.find_arrangement(state, 1, "built-in + 1 external")
        expect.equal(arrangement.monitors, {
            { slot_key = "built-in", desktop_count = 3 },
            { slot_key = "external 1", desktop_count = 2, shown_desktop_number = 2 },
        })
        expect.equal(arrangement.focused_slot_key, "external 1")
        expect.equal(arrangement.focus, nil)
        expect.equal(state.format_version, profile_state.FORMAT_VERSION)
    end,

    a_shown_desktop_below_1_is_dropped = function()
        local function decode_arrangement(format_version, raw_arrangement)
            raw_arrangement.monitor_configuration_key = "built-in"
            raw_arrangement.windows = {}
            local state = profile_state.decode({
                format_version = format_version,
                monitor_matching = "by_count",
                profiles = {
                    ["1"] = { number = 1, arrangements = { ["built-in"] = raw_arrangement } },
                },
            })
            return profile_state.find_arrangement(state, 1, "built-in")
        end
        local current = decode_arrangement(2, {
            monitors = { { slot_key = "built-in", desktop_count = 2, shown_desktop_number = 0 } },
            focused_slot_key = 7,
        })
        expect.equal(current.monitors, { { slot_key = "built-in", desktop_count = 2 } })
        expect.equal(current.focused_slot_key, nil)
        local migrated = decode_arrangement(1, {
            monitors = { { slot_key = "built-in", desktop_count = 2 } },
            focus = { slot_key = "built-in", desktop_number = 0 },
        })
        expect.equal(migrated.monitors, { { slot_key = "built-in", desktop_count = 2 } })
        expect.equal(migrated.focused_slot_key, nil)
    end,

    an_old_desktop_count_is_limited_to_the_kept_count_and_the_recorded_windows = function()
        local function record_on(window_id, slot_key, desktop_number)
            return {
                window_id = window_id,
                bundle_id = "com.apple.Safari",
                slot_key = slot_key,
                desktop_number = desktop_number,
                is_out_of_sight = false,
            }
        end
        local state = profile_state.decode({
            format_version = 1,
            monitor_matching = "by_count",
            desktop_counts = { kept = { ["built-in"] = 3, ["external 1"] = 4 } },
            profiles = {
                ["1"] = {
                    number = 1,
                    arrangements = {
                        ["built-in + 1 external"] = {
                            monitor_configuration_key = "built-in + 1 external",
                            monitors = {
                                { slot_key = "built-in", desktop_count = 7 },
                                { slot_key = "external 1", desktop_count = 2 },
                                { slot_key = "external 2", desktop_count = 5 },
                            },
                            windows = {
                                record_on(41, "built-in", 5),
                                record_on(42, "built-in", 2),
                                record_on(43, "external 1", 2),
                            },
                        },
                        ["built-in"] = {
                            monitor_configuration_key = "built-in",
                            monitors = { { slot_key = "built-in", desktop_count = 6 } },
                            windows = { record_on(44, "built-in", 1) },
                        },
                    },
                },
            },
        })
        expect.equal(profile_state.find_arrangement(state, 1, "built-in + 1 external").monitors, {
            { slot_key = "built-in", desktop_count = 5 },
            { slot_key = "external 1", desktop_count = 2 },
            { slot_key = "external 2", desktop_count = 5 },
        })
        expect.equal(
            profile_state.find_arrangement(state, 1, "built-in").monitors,
            { { slot_key = "built-in", desktop_count = 3 } }
        )
        local current = profile_state.decode(state)
        expect.equal(current, state)
    end,
}
