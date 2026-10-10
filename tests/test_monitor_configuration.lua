local expect = require("tests.expect")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")

local BUILTIN = {
    uuid = "BUILTIN-UUID",
    name = "Built-in Retina Display",
    is_builtin = true,
    frame = { x = 0, y = 25, w = 1440, h = 875 },
}
local LG_RIGHT = {
    uuid = "LG-UUID",
    name = "LG TV SSCR2",
    is_builtin = false,
    frame = { x = 1440, y = 0, w = 1872, h = 1053 },
}
local DELL_LEFT = {
    uuid = "DELL-UUID",
    name = "DELL U2720Q",
    is_builtin = false,
    frame = { x = -2560, y = 0, w = 2560, h = 1440 },
}

return {
    by_count_names_external_monitors_by_position = function()
        local configuration = monitor_configuration.describe(
            { LG_RIGHT, BUILTIN, DELL_LEFT },
            monitor_matching.BY_COUNT
        )
        expect.equal(configuration.key, "built-in + 2 external")
        expect.equal(configuration.slots, {
            { slot_key = "built-in", screen_uuid = "BUILTIN-UUID" },
            { slot_key = "external 1", screen_uuid = "DELL-UUID" },
            { slot_key = "external 2", screen_uuid = "LG-UUID" },
        })
    end,

    by_count_ignores_which_external_monitor_is_connected = function()
        local with_lg =
            monitor_configuration.describe({ BUILTIN, LG_RIGHT }, monitor_matching.BY_COUNT)
        local with_dell =
            monitor_configuration.describe({ BUILTIN, DELL_LEFT }, monitor_matching.BY_COUNT)
        expect.equal(with_lg.key, with_dell.key)
    end,

    by_count_names_external_only_and_builtin_only = function()
        expect.equal(
            monitor_configuration.describe({ LG_RIGHT }, monitor_matching.BY_COUNT).key,
            "1 external"
        )
        expect.equal(
            monitor_configuration.describe({ BUILTIN }, monitor_matching.BY_COUNT).key,
            "built-in"
        )
    end,

    by_identity_tells_external_monitors_apart = function()
        local with_lg =
            monitor_configuration.describe({ BUILTIN, LG_RIGHT }, monitor_matching.BY_IDENTITY)
        local with_dell =
            monitor_configuration.describe({ BUILTIN, DELL_LEFT }, monitor_matching.BY_IDENTITY)
        expect.equal(with_lg.key, "built-in + LG TV SSCR2")
        expect.equal(with_dell.key, "built-in + DELL U2720Q")
    end,

    by_identity_numbers_monitors_of_the_same_name = function()
        local second_lg = {
            uuid = "LG2-UUID",
            name = "LG TV SSCR2",
            is_builtin = false,
            frame = { x = 3312, y = 0, w = 1872, h = 1053 },
        }
        local configuration =
            monitor_configuration.describe({ second_lg, LG_RIGHT }, monitor_matching.BY_IDENTITY)
        expect.equal(configuration.key, "LG TV SSCR2 + LG TV SSCR2 #2")
        expect.equal(configuration.slots[1].screen_uuid, "LG-UUID")
    end,

    describe_rejects_an_empty_screen_list = function()
        expect.raises(function()
            monitor_configuration.describe({}, monitor_matching.BY_COUNT)
        end, "at least one screen")
    end,

    describe_rejects_an_unknown_matching = function()
        expect.raises(function()
            monitor_configuration.describe({ BUILTIN }, "by_colour")
        end, 'unknown monitor matching "by_colour"')
    end,

    find_slot_of_screen_returns_nil_for_a_missing_screen = function()
        local configuration = monitor_configuration.describe({ BUILTIN }, monitor_matching.BY_COUNT)
        expect.equal(monitor_configuration.find_slot_of_screen(configuration, "LG-UUID"), nil)
        expect.equal(
            monitor_configuration.find_slot(configuration, "built-in").screen_uuid,
            "BUILTIN-UUID"
        )
    end,
}
