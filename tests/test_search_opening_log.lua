local expect = require("tests.expect")
local search_opening_log = require("desktop_manager.core.search_opening_log")

return {
    a_full_opening_reads_with_its_previews_its_list_of_the_window_server_and_its_keys = function()
        expect.equal(
            search_opening_log.describe({
                window_count = 12,
                shown_after = 0.012,
                first_preview_after = 0.064,
                last_preview_after = 1.105,
                preview_count = 12,
                requested_preview_count = 12,
                preview_blocking_seconds = 0.93,
                longest_preview_blocking_seconds = 0.16,
                server_list_after = 0.203,
                server_list_blocking_seconds = 0.045,
                key_count = 5,
                longest_key_wait_seconds = 0.12,
            }),
            "search of 12 windows: shown after 0.012 seconds, first preview after 0.064 seconds,"
                .. " 12 of 12 previews by 1.105 seconds, blocking Hammerspoon for 0.930 seconds"
                .. " in total and 0.160 seconds at most, list of the window server after 0.203"
                .. " seconds, blocking Hammerspoon for 0.045 seconds, 5 keys, waiting 0.120"
                .. " seconds at most"
        )
    end,

    an_opening_closed_before_any_preview_list_or_key_reads_without_them = function()
        expect.equal(
            search_opening_log.describe({
                window_count = 1,
                shown_after = 0.004,
                preview_count = 0,
                requested_preview_count = 1,
                preview_blocking_seconds = 0,
                longest_preview_blocking_seconds = 0,
                key_count = 0,
            }),
            "search of 1 window: shown after 0.004 seconds, no preview,"
                .. " list of the window server not back, no key"
        )
    end,
}
