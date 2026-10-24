local expect = require("tests.expect")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local window_matching = require("desktop_manager.core.window_matching")

local MATCH_TITLE = missing_window_policy.MATCH_TITLE
local MATCH_ID_ALONE = missing_window_policy.MATCH_ID_ALONE
local BY_ID = match_windows_by.ID
local BY_TITLE = match_windows_by.TITLE

---@param window_id integer|nil
---@param bundle_id string
---@param title string
---@return WindowRecord
local function record(window_id, bundle_id, title)
    return {
        window_id = window_id,
        bundle_id = bundle_id,
        app_name = bundle_id,
        title = title,
        is_out_of_sight = false,
    }
end

return {
    the_window_id_decides_before_the_title = function()
        local records = { record(41, "com.apple.Safari", "Inbox") }
        local open_windows = {
            { window_id = 7, bundle_id = "com.apple.Safari", title = "Inbox" },
            { window_id = 41, bundle_id = "com.apple.Safari", title = "News" },
        }
        local result =
            window_matching.match_records_to_open_windows(BY_ID, MATCH_TITLE, records, open_windows)
        expect.equal(result.matches[1].window_id, 41)
    end,

    the_title_decides_when_the_window_was_reopened = function()
        local records =
            { record(41, "com.apple.Safari", "Inbox"), record(42, "com.apple.Safari", "News") }
        local open_windows = {
            { window_id = 90, bundle_id = "com.apple.Safari", title = "News" },
            { window_id = 91, bundle_id = "com.apple.Safari", title = "Inbox" },
        }
        local result =
            window_matching.match_records_to_open_windows(BY_ID, MATCH_TITLE, records, open_windows)
        expect.equal(result.matches[1].window_id, 91)
        expect.equal(result.matches[2].window_id, 90)
    end,

    the_policy_that_opens_new_windows_matches_by_id_alone = function()
        local records = { record(41, "com.apple.Safari", "Inbox") }
        local open_windows = { { window_id = 7, bundle_id = "com.apple.Safari", title = "Inbox" } }
        local result = window_matching.match_records_to_open_windows(
            BY_ID,
            MATCH_ID_ALONE,
            records,
            open_windows
        )
        expect.equal(result.matches, {})
        expect.raises(function()
            window_matching.match_records_to_open_windows(BY_ID, "guess", records, open_windows)
        end, 'unknown missing window policy "guess"')
    end,

    an_open_window_of_the_same_application_alone_stays_unmatched = function()
        local records = { record(41, "com.apple.Safari", "Inbox") }
        local open_windows = { { window_id = 7, bundle_id = "com.apple.Safari", title = "News" } }
        local result =
            window_matching.match_records_to_open_windows(BY_ID, MATCH_TITLE, records, open_windows)
        expect.equal(result.matches, {})
        expect.equal(#result.unmatched_records, 1)
    end,

    a_reopened_window_matches_by_title = function()
        local records = { record(42, "com.apple.TextEdit", "Untitled") }
        local open_windows = {
            { window_id = 91, bundle_id = "com.apple.TextEdit", title = "Notes.txt" },
            { window_id = 90, bundle_id = "com.apple.TextEdit", title = "Untitled" },
        }
        local result = window_matching.match_records_to_reopened_windows(records, open_windows)
        expect.equal(result.matches[1].window_id, 90)
    end,

    a_closed_window_is_listed_and_read_once_per_application = function()
        local recorded = {
            record(42, "com.apple.TextEdit", "Untitled"),
            record(42, "com.apple.TextEdit", "Untitled"),
            record(42, "com.apple.Safari", "Inbox"),
            record(43, "com.apple.TextEdit", "Open"),
            record(nil, "com.apple.TextEdit", "Never shown"),
            record(44, "com.apple.TextEdit", "On a desktop"),
        }
        local gone_reads = {}
        local closed = window_matching.list_closed_records(recorded, function(window_id)
            return window_id == 43
        end, function(window_id)
            table.insert(gone_reads, window_id)
            return window_id ~= 44
        end)
        expect.equal(closed, { recorded[1], recorded[3] })
        expect.equal(gone_reads, { 42, 42, 44 })
    end,

    a_reopened_window_needs_more_than_the_same_application = function()
        local records = { record(41, "com.apple.Safari", "Inbox") }
        local open_windows = { { window_id = 90, bundle_id = "com.apple.Safari", title = "News" } }
        local result = window_matching.match_records_to_reopened_windows(records, open_windows)
        expect.equal(result.matches, {})
    end,

    each_window_matches_one_record = function()
        local records = { record(nil, "com.apple.Notes", "A"), record(nil, "com.apple.Notes", "B") }
        local open_windows = { { window_id = 3, bundle_id = "com.apple.Notes", title = "B" } }
        local result =
            window_matching.match_records_to_open_windows(BY_ID, MATCH_TITLE, records, open_windows)
        expect.equal(#result.matches, 1)
        expect.equal(result.matches[1].record.title, "B")
        expect.equal(result.unmatched_records[1].title, "A")
    end,

    the_title_decides_before_the_window_id = function()
        local records =
            { record(41, "com.apple.Safari", "Inbox"), record(42, "com.apple.Safari", "News") }
        local open_windows = {
            { window_id = 41, bundle_id = "com.apple.Safari", title = "News" },
            { window_id = 42, bundle_id = "com.apple.Safari", title = "Inbox" },
        }
        local result = window_matching.match_records_to_open_windows(
            BY_TITLE,
            MATCH_ID_ALONE,
            records,
            open_windows
        )
        expect.equal(result.matches[1].window_id, 42)
        expect.equal(result.matches[2].window_id, 41)
    end,

    of_two_windows_with_the_title_the_one_with_the_recorded_id_matches = function()
        local records = { record(41, "com.googlecode.iterm2", "zsh") }
        local open_windows = {
            { window_id = 7, bundle_id = "com.googlecode.iterm2", title = "zsh" },
            { window_id = 41, bundle_id = "com.googlecode.iterm2", title = "zsh" },
        }
        local result = window_matching.match_records_to_open_windows(
            BY_TITLE,
            MATCH_TITLE,
            records,
            open_windows
        )
        expect.equal(result.matches[1].window_id, 41)
    end,

    the_window_id_decides_when_no_title_matches = function()
        local records =
            { record(41, "com.apple.Safari", "Inbox"), record(42, "com.apple.Safari", "") }
        local open_windows = {
            { window_id = 41, bundle_id = "com.apple.Safari", title = "News" },
            { window_id = 7, bundle_id = "com.apple.Safari", title = "" },
            { window_id = 42, bundle_id = "com.apple.Safari", title = "Weather" },
        }
        local result = window_matching.match_records_to_open_windows(
            BY_TITLE,
            MATCH_ID_ALONE,
            records,
            open_windows
        )
        expect.equal(result.matches[1].window_id, 41)
        expect.equal(result.matches[2].window_id, 42)
        expect.raises(function()
            window_matching.match_records_to_open_windows(
                "guess",
                MATCH_ID_ALONE,
                records,
                open_windows
            )
        end, 'unknown way to match windows "guess"')
    end,

    a_record_of_an_application_without_windows_stays_unmatched = function()
        local records = { record(8, "com.google.Docs", "Paper") }
        local result =
            window_matching.match_records_to_open_windows(BY_ID, MATCH_TITLE, records, {})
        expect.equal(#result.matches, 0)
        expect.equal(result.unmatched_records[1].bundle_id, "com.google.Docs")
    end,
}
