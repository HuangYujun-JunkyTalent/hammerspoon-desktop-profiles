local expect = require("tests.expect")
local window_matching = require("desktop_manager.core.window_matching")

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
        local result = window_matching.match_records_to_open_windows(records, live)
        expect.equal(result.matches[1].window_id, 41)
    end,

    the_title_decides_when_the_window_was_reopened = function()
        local records =
            { record(41, "com.apple.Safari", "Inbox"), record(42, "com.apple.Safari", "News") }
        local live = {
            { window_id = 90, bundle_id = "com.apple.Safari", title = "News" },
            { window_id = 91, bundle_id = "com.apple.Safari", title = "Inbox" },
        }
        local result = window_matching.match_records_to_open_windows(records, live)
        expect.equal(result.matches[1].window_id, 91)
        expect.equal(result.matches[2].window_id, 90)
    end,

    the_application_decides_last_for_a_launched_application = function()
        local records = { record(nil, "com.microsoft.Word", "Draft.docx") }
        local live = { { window_id = 5, bundle_id = "com.microsoft.Word", title = "Draft 2.docx" } }
        local result = window_matching.match_records_to_launched_windows(records, live)
        expect.equal(result.matches[1].window_id, 5)
        expect.equal(#result.unmatched_records, 0)
    end,

    an_open_window_of_the_same_application_alone_stays_unmatched = function()
        local records = { record(41, "com.apple.Safari", "Inbox") }
        local live = { { window_id = 7, bundle_id = "com.apple.Safari", title = "News" } }
        local result = window_matching.match_records_to_open_windows(records, live)
        expect.equal(result.matches, {})
        expect.equal(#result.unmatched_records, 1)
    end,

    each_window_matches_one_record = function()
        local records = { record(nil, "com.apple.Notes", "A"), record(nil, "com.apple.Notes", "B") }
        local live = { { window_id = 3, bundle_id = "com.apple.Notes", title = "B" } }
        local result = window_matching.match_records_to_launched_windows(records, live)
        expect.equal(#result.matches, 1)
        expect.equal(result.matches[1].record.title, "B")
        expect.equal(result.unmatched_records[1].title, "A")
    end,

    a_record_of_an_application_without_windows_stays_unmatched = function()
        local records = { record(8, "com.google.Docs", "Paper") }
        local result = window_matching.match_records_to_open_windows(records, {})
        expect.equal(#result.matches, 0)
        expect.equal(result.unmatched_records[1].bundle_id, "com.google.Docs")
    end,
}
