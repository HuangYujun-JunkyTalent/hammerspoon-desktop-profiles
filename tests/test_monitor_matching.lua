local expect = require("tests.expect")
local monitor_matching = require("desktop_manager.core.monitor_matching")

return {
    next_after_cycles_through_both_matchings = function()
        expect.equal(
            monitor_matching.next_after(monitor_matching.BY_COUNT),
            monitor_matching.BY_IDENTITY
        )
        expect.equal(
            monitor_matching.next_after(monitor_matching.BY_IDENTITY),
            monitor_matching.BY_COUNT
        )
    end,

    is_valid_rejects_other_values = function()
        expect.equal(monitor_matching.is_valid("by_count"), true)
        expect.equal(monitor_matching.is_valid("by_colour"), false)
        expect.equal(monitor_matching.is_valid(nil), false)
    end,

    label_of_rejects_an_unknown_matching = function()
        expect.raises(function()
            monitor_matching.label_of("by_colour")
        end, 'unknown monitor matching "by_colour"')
    end,
}
