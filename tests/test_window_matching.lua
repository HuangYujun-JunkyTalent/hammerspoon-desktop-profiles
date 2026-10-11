local expect = require("tests.expect")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local window_matching = require("desktop_manager.core.window_matching")

local MATCH_TITLE = missing_window_policy.MATCH_TITLE_OR_OPEN_NEW_WINDOW
local OPEN_NEW = missing_window_policy.OPEN_NEW_WINDOW

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
        local live = {
            { window_id = 7, bundle_id = "com.apple.Safari", title = "Inbox" },
            { window_id = 41, bundle_id = "com.apple.Safari", title = "News" },
        }
        local result = window_matching.match_records_to_open_windows(MATCH_TITLE, records, live)
        expect.equal(result.matches[1].window_id, 41)
    end,

    the_title_decides_when_the_window_was_reopened = function()
        local records =
            { record(41, "com.apple.Safari", "Inbox"), record(42, "com.apple.Safari", "News") }
        local live = {
            { window_id = 90, bundle_id = "com.apple.Safari", title = "News" },
            { window_id = 91, bundle_id = "com.apple.Safari", title = "Inbox" },
        }
        local result = window_matching.match_records_to_open_windows(MATCH_TITLE, records, live)
        expect.equal(result.matches[1].window_id, 91)
        expect.equal(result.matches[2].window_id, 90)
    end,

    the_policy_that_opens_new_windows_matches_by_id_alone = function()
        local records = { record(41, "com.apple.Safari", "Inbox") }
        local live = { { window_id = 7, bundle_id = "com.apple.Safari", title = "Inbox" } }
        local result = window_matching.match_records_to_open_windows(OPEN_NEW, records, live)
        expect.equal(result.matches, {})
        expect.raises(function()
            window_matching.match_records_to_open_windows("guess", records, live)
        end, 'unknown missing window policy "guess"')
    end,

    an_open_window_of_the_same_application_alone_stays_unmatched = function()
        local records = { record(41, "com.apple.Safari", "Inbox") }
        local live = { { window_id = 7, bundle_id = "com.apple.Safari", title = "News" } }
        local result = window_matching.match_records_to_open_windows(MATCH_TITLE, records, live)
        expect.equal(result.matches, {})
        expect.equal(#result.unmatched_records, 1)
    end,

    a_reopened_window_matches_by_title = function()
        local records = { record(42, "com.apple.TextEdit", "Untitled") }
        local live = {
            { window_id = 91, bundle_id = "com.apple.TextEdit", title = "Notes.txt" },
            { window_id = 90, bundle_id = "com.apple.TextEdit", title = "Untitled" },
        }
        local result = window_matching.match_records_to_reopened_windows(records, live)
        expect.equal(result.matches[1].window_id, 90)
    end,

    a_reopened_window_needs_more_than_the_same_application = function()
        local records = { record(41, "com.apple.Safari", "Inbox") }
        local live = { { window_id = 90, bundle_id = "com.apple.Safari", title = "News" } }
        local result = window_matching.match_records_to_reopened_windows(records, live)
        expect.equal(result.matches, {})
    end,

    each_window_matches_one_record = function()
        local records = { record(nil, "com.apple.Notes", "A"), record(nil, "com.apple.Notes", "B") }
        local live = { { window_id = 3, bundle_id = "com.apple.Notes", title = "B" } }
        local result = window_matching.match_records_to_open_windows(MATCH_TITLE, records, live)
        expect.equal(#result.matches, 1)
        expect.equal(result.matches[1].record.title, "B")
        expect.equal(result.unmatched_records[1].title, "A")
    end,

    a_record_of_an_application_without_windows_stays_unmatched = function()
        local records = { record(8, "com.google.Docs", "Paper") }
        local result = window_matching.match_records_to_open_windows(MATCH_TITLE, records, {})
        expect.equal(#result.matches, 0)
        expect.equal(result.unmatched_records[1].bundle_id, "com.google.Docs")
    end,
}
