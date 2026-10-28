local app_pool = require("desktop_manager.core.app_pool")
local expect = require("tests.expect")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
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
        local renamed = profile_state.with_profile_name(state, 2, "  Writing  ")
        expect.equal(profile_state.profile_or_default(renamed, 2).name, "Writing")
        expect.equal(state.profiles["2"], nil)
    end,

    a_shown_desktop_is_recorded_with_the_focus_in_a_new_state = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        state = profile_state.with_arrangement(state, 3, ARRANGEMENT)
        local shown = expect.present(
            profile_state.with_shown_desktop(state, 3, "built-in", "built-in", 2),
            "the state with the shown desktop"
        )
        local arrangement = expect.present(
            profile_state.find_arrangement(shown, 3, "built-in"),
            "the arrangement of profile 3"
        )
        expect.equal(arrangement.monitors[1].shown_desktop_number, 2)
        expect.equal(arrangement.focused_slot_key, "built-in")
        expect.equal(arrangement.windows, ARRANGEMENT.windows)
        expect.equal(
            profile_state.find_arrangement(state, 3, "built-in").monitors[1].shown_desktop_number,
            1
        )
        expect.equal(
            profile_state.with_shown_desktop(state, 3, "built-in + 1 external", "built-in", 2),
            nil
        )
    end,

    rename_rejects_a_blank_name = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        expect.raises(function()
            profile_state.with_profile_name(state, 2, "   ")
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
        expect.equal(
            profile_state.rename_of(ARRANGEMENT.windows[1], 90),
            { bundle_id = "com.apple.Safari", old_window_id = 41, new_window_id = 90 }
        )
    end,

    an_arrangement_is_kept_per_monitor_configuration = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        state = profile_state.with_arrangement(state, 3, ARRANGEMENT)
        expect.equal(profile_state.find_arrangement(state, 3, "built-in"), ARRANGEMENT)
        expect.equal(profile_state.find_arrangement(state, 3, "built-in + 1 external"), nil)
    end,

    the_recorded_window_ids_leave_out_a_record_without_an_id = function()
        local arrangement = {
            monitor_configuration_key = ARRANGEMENT.monitor_configuration_key,
            monitors = ARRANGEMENT.monitors,
            focused_slot_key = ARRANGEMENT.focused_slot_key,
            windows = {
                ARRANGEMENT.windows[1],
                {
                    bundle_id = "com.apple.Notes",
                    app_name = "Notes",
                    title = "Shopping",
                    slot_key = "built-in",
                    desktop_number = 1,
                    unit_frame = { x = 0.5, y = 0, w = 0.5, h = 1 },
                    is_out_of_sight = false,
                },
            },
        }
        expect.equal(profile_state.list_recorded_window_ids(arrangement), { 41 })
        expect.equal(profile_state.list_recorded_window_ids(nil), {})
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
        local configuration = monitor_configuration.describe({
            {
                uuid = "BUILTIN-UUID",
                name = "Built-in Retina Display",
                is_builtin = true,
                frame = { x = 0, y = 25, w = 1440, h = 875 },
            },
        }, monitor_matching.BY_COUNT)
        local notes_arrangement = {
            monitor_configuration_key = "built-in",
            monitors = {},
            windows = {
                {
                    window_id = 77,
                    bundle_id = "com.apple.Notes",
                    app_name = "Notes",
                    title = "Shopping",
                    slot_key = "built-in",
                    desktop_number = 1,
                    unit_frame = { x = 0, y = 0, w = 0.5, h = 1 },
                    is_out_of_sight = false,
                },
            },
        }
        local numbered = profile_state.with_default_app_numbers(
            state,
            profile_state.NO_PROFILE_NUMBER,
            notes_arrangement,
            configuration,
            9
        )
        expect.equal(profile_state.profile_or_default(numbered, 0).app_numbers, {
            {
                number = 1,
                bundle_id = "com.apple.Notes",
                app_name = "Notes",
                is_chosen_by_user = false,
            },
            {
                number = 2,
                bundle_id = "com.apple.Safari",
                app_name = "Safari",
                is_chosen_by_user = true,
            },
        })
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
        local state = expect.present(profile_state.decode(raw), "the decoded state")
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
        ---@type table a state of the format before the pool, with a list of managed applications
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
        ---@type table a state without the desktop counts, and then with a wrong reading
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
            profile_state.with_profile_name(
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
        local decoded = expect.present(profile_state.decode(state), "the decoded state")
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
        local state = expect.present(
            profile_state.decode({
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
            }),
            "the decoded state"
        )
        expect.equal(profile_state.find_arrangement(state, 1, "built-in + 1 external"), {
            monitor_configuration_key = "built-in + 1 external",
            monitors = {
                { slot_key = "built-in", desktop_count = 3 },
                { slot_key = "external 1", desktop_count = 2, shown_desktop_number = 2 },
            },
            focused_slot_key = "external 1",
            windows = {},
        })
        expect.equal(state.format_version, profile_state.FORMAT_VERSION)
    end,

    a_shown_desktop_below_1_is_dropped = function()
        local function decode_arrangement(format_version, raw_arrangement)
            raw_arrangement.monitor_configuration_key = "built-in"
            raw_arrangement.windows = {}
            local state = expect.present(
                profile_state.decode({
                    format_version = format_version,
                    monitor_matching = "by_count",
                    profiles = {
                        ["1"] = { number = 1, arrangements = { ["built-in"] = raw_arrangement } },
                    },
                }),
                "the decoded state"
            )
            return expect.present(
                profile_state.find_arrangement(state, 1, "built-in"),
                "the arrangement of profile 1"
            )
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
        local state = expect.present(
            profile_state.decode({
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
            }),
            "the decoded state"
        )
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

    decode_round_trips_a_pause_and_drops_a_pause_without_an_active_profile = function()
        local active = profile_state.with_active_profile_number(
            profile_state.new_state(monitor_matching.BY_COUNT),
            1
        )
        local paused = profile_state.with_last_seen_login_time(
            profile_state.with_last_seen_macos_start_time(
                profile_state.with_active_profile_paused(active),
                1729500000
            ),
            1729500060
        )
        expect.equal(profile_state.decode(paused), paused)
        expect.equal(profile_state.decode(active).last_seen_macos_start_time, nil)
        expect.equal(profile_state.decode(active).last_seen_login_time, nil)
        local without_field = profile_state.new_state(monitor_matching.BY_COUNT)
        without_field.active_profile_number = 1
        without_field.is_active_profile_paused = nil
        expect.equal(profile_state.decode(without_field).is_active_profile_paused, false)
        local inactive = profile_state.new_state(monitor_matching.BY_COUNT)
        inactive.is_active_profile_paused = true
        expect.equal(profile_state.decode(inactive).is_active_profile_paused, false)
    end,

    a_change_of_the_active_profile_ends_the_pause = function()
        local paused = profile_state.with_active_profile_paused(
            profile_state.with_active_profile_number(
                profile_state.new_state(monitor_matching.BY_COUNT),
                1
            )
        )
        for _, number in ipairs({ 1, 2 }) do
            local switched = profile_state.with_active_profile_number(paused, number)
            expect.equal(switched.is_active_profile_paused, false)
            expect.equal(profile_state.find_profile_number_to_update(switched, "built-in"), number)
        end
        expect.equal(
            profile_state.with_active_profile_number(paused, nil).is_active_profile_paused,
            false
        )
        expect.equal(profile_state.find_profile_number_to_update(paused, "built-in"), nil)
        expect.equal(
            profile_state.find_profile_number_to_update(
                profile_state.with_pause_ended(paused),
                "built-in"
            ),
            1
        )
    end,

    only_an_active_profile_can_be_paused = function()
        expect.raises(function()
            profile_state.with_active_profile_paused(
                profile_state.new_state(monitor_matching.BY_COUNT)
            )
        end, "no profile is active")
    end,

    a_profile_arranges_every_configuration_until_it_leaves_one_to_macos = function()
        local state = profile_state.with_active_profile_number(
            profile_state.new_state(monitor_matching.BY_COUNT),
            1
        )
        expect.equal(profile_state.manages_configuration(state, 1, "built-in"), true)
        local left = profile_state.with_configuration_left_to_macos(state, 1, "built-in")
        left = profile_state.with_configuration_left_to_macos(left, 1, "built-in")
        expect.equal(profile_state.profile_or_default(left, 1).unmanaged_configuration_keys, {
            "built-in",
        })
        expect.equal(profile_state.manages_configuration(left, 1, "built-in"), false)
        expect.equal(profile_state.manages_configuration(left, 1, "built-in + 1 external"), true)
        expect.equal(profile_state.manages_configuration(left, 2, "built-in"), true)
        expect.equal(profile_state.find_profile_number_to_update(left, "built-in"), nil)
        expect.equal(profile_state.find_profile_number_to_update(left, "built-in + 1 external"), 1)
        local managed = profile_state.with_configuration_managed(left, 1, "built-in")
        expect.equal(profile_state.manages_configuration(managed, 1, "built-in"), true)
        expect.equal(profile_state.find_profile_number_to_update(managed, "built-in"), 1)
    end,

    profile_0_leaves_no_configuration_to_macos = function()
        expect.raises(function()
            profile_state.with_configuration_left_to_macos(
                profile_state.new_state(monitor_matching.BY_COUNT),
                profile_state.NO_PROFILE_NUMBER,
                "built-in"
            )
        end, "profile 0 arranges no monitor configuration")
    end,

    the_configurations_left_to_macos_survive_the_state_file = function()
        local state = profile_state.with_configuration_left_to_macos(
            profile_state.with_configuration_left_to_macos(
                profile_state.new_state(monitor_matching.BY_COUNT),
                2,
                "built-in"
            ),
            2,
            "1 external"
        )
        local decoded = expect.present(profile_state.decode(state), "the decoded state")
        expect.equal(
            profile_state.profile_or_default(decoded, 2).unmanaged_configuration_keys,
            { "1 external", "built-in" }
        )
        local raw = profile_state.new_state(monitor_matching.BY_COUNT) --[[@as table]]
        raw.profiles["1"] = { number = 1, name = "Writing", arrangements = {}, app_numbers = {} }
        raw.profiles["3"] = {
            number = 3,
            name = "Reading",
            arrangements = {},
            app_numbers = {},
            unmanaged_configuration_keys = { "built-in", 4, "built-in" },
        }
        local older = expect.present(profile_state.decode(raw), "the decoded older state")
        expect.equal(profile_state.profile_or_default(older, 1).unmanaged_configuration_keys, {})
        expect.equal(profile_state.profile_or_default(older, 3).unmanaged_configuration_keys, {
            "built-in",
        })
    end,

    the_named_bundle_ids_come_from_the_records_the_numbers_and_the_managed_list = function()
        local state = profile_state.new_state(monitor_matching.BY_COUNT)
        state = profile_state.with_arrangement(state, 3, ARRANGEMENT)
        state = profile_state.with_app_numbers(state, profile_state.NO_PROFILE_NUMBER, {
            { number = 2, bundle_id = "org.asyar", app_name = "asyar", is_chosen_by_user = true },
        })
        local skipping = app_pool.with_listed(app_pool.new(), "com.apple.Siri", "Siri", true)
        local managing = app_pool.with_mode(skipping, app_pool.MANAGE_LISTED)
        state = profile_state.with_app_pool(
            state,
            app_pool.with_listed(managing, "pro.betterdisplay.BetterDisplay", "BD", true)
        )
        local expected = { ["org.asyar"] = true, ["pro.betterdisplay.BetterDisplay"] = true }
        for _, record in ipairs(ARRANGEMENT.windows) do
            expected[record.bundle_id] = true
        end
        expect.equal(profile_state.list_named_bundle_ids(state), expected)
        local back_to_skipping = app_pool.with_mode(state.app_pool, app_pool.SKIP_LISTED)
        state = profile_state.with_app_pool(state, back_to_skipping)
        expected["pro.betterdisplay.BetterDisplay"] = nil
        expect.equal(profile_state.list_named_bundle_ids(state), expected)
    end,
}
