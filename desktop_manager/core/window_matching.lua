local window_matching = {}

---A saved window of an arrangement.
---The location fields are nil when the window was minimized before its desktop was ever seen.
---@class WindowRecord
---@field window_id integer|nil
---@field bundle_id string
---@field app_name string
---@field title string
---@field slot_key string|nil
---@field desktop_number integer|nil
---@field unit_frame Rect|nil
---@field is_minimized boolean

---@class LiveWindow
---@field window_id integer
---@field bundle_id string
---@field title string

---@class WindowMatch
---@field record WindowRecord
---@field window_id integer

---@class WindowMatchResult
---@field matches WindowMatch[]
---@field unmatched_records WindowRecord[]

---@alias MatchCriterion fun(record: WindowRecord, window: LiveWindow): boolean

---@type MatchCriterion[]
local CRITERIA_FROM_STRICTEST = {
    function(record, window)
        return record.window_id == window.window_id and record.bundle_id == window.bundle_id
    end,
    function(record, window)
        return record.bundle_id == window.bundle_id and record.title == window.title
    end,
    function(record, window)
        return record.bundle_id == window.bundle_id
    end,
}

---Pairs each saved record with at most one live window, and each window with at most one record.
---A window keeps its id while it stays open, so the id decides first.
---A window reopened by its application gets a new id.
---The title therefore decides next, and the application last.
---@param records WindowRecord[]
---@param live_windows LiveWindow[]
---@return WindowMatchResult
function window_matching.match_records_to_windows(records, live_windows)
    local used_window_ids = {}
    local window_id_by_record_index = {}
    for _, criterion in ipairs(CRITERIA_FROM_STRICTEST) do
        for record_index, record in ipairs(records) do
            if not window_id_by_record_index[record_index] then
                for _, window in ipairs(live_windows) do
                    if not used_window_ids[window.window_id] and criterion(record, window) then
                        used_window_ids[window.window_id] = true
                        window_id_by_record_index[record_index] = window.window_id
                        break
                    end
                end
            end
        end
    end
    local matches, unmatched_records = {}, {}
    for record_index, record in ipairs(records) do
        local window_id = window_id_by_record_index[record_index]
        if window_id then
            table.insert(matches, { record = record, window_id = window_id })
        else
            table.insert(unmatched_records, record)
        end
    end
    return { matches = matches, unmatched_records = unmatched_records }
end

return window_matching
