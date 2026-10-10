local window_matching = {}

---A saved window of an arrangement.
---A window is out of sight when it is minimized or its application is hidden.
---The location fields are nil when the window was out of sight before its desktop was ever seen.
---@class WindowRecord
---@field window_id integer|nil
---@field bundle_id string
---@field app_name string
---@field title string
---@field slot_key string|nil
---@field desktop_number integer|nil
---@field unit_frame Rect|nil
---@field is_out_of_sight boolean
---@field document string|nil the file or URL that the window shows, when its application says

---@class LiveWindow
---@field window_id integer
---@field bundle_id string
---@field title string
---@field document string|nil

---@class WindowMatch
---@field record WindowRecord
---@field window_id integer

---@class WindowMatchResult
---@field matches WindowMatch[]
---@field unmatched_records WindowRecord[]

---@alias MatchCriterion fun(record: WindowRecord, window: LiveWindow): boolean

---@type MatchCriterion
local function has_same_id(record, window)
    return record.window_id == window.window_id and record.bundle_id == window.bundle_id
end

---@type MatchCriterion
local function has_same_title(record, window)
    return record.bundle_id == window.bundle_id and record.title == window.title
end

---@type MatchCriterion
local function has_same_document(record, window)
    return record.bundle_id == window.bundle_id
        and record.document ~= nil
        and record.document ~= ""
        and record.document == window.document
end

---@type MatchCriterion
local function has_same_application(record, window)
    return record.bundle_id == window.bundle_id
end

---Pairs each saved record with at most one live window, and each window with at most one record,
---trying the criteria in order.
---@param criteria MatchCriterion[]
---@param records WindowRecord[]
---@param live_windows LiveWindow[]
---@return WindowMatchResult
local function match_by_criteria(criteria, records, live_windows)
    local used_window_ids = {}
    local window_id_by_record_index = {}
    for _, criterion in ipairs(criteria) do
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

---Matches the records to windows that were open before the switch.
---A window keeps its id while it stays open, so the id decides first.
---A window that its application reopened has a new id, and its title decides next.
---@param records WindowRecord[]
---@param live_windows LiveWindow[]
---@return WindowMatchResult
function window_matching.match_records_to_open_windows(records, live_windows)
    return match_by_criteria({ has_same_id, has_same_title }, records, live_windows)
end

---Matches the records of windows that no longer exist to open windows that no profile recorded.
---macOS gives a window that its application reopens a new id, so the document decides first and
---the title next.
---The place is left out, because macOS opens a new window at the place of the last closed one.
---@param records WindowRecord[]
---@param live_windows LiveWindow[]
---@return WindowMatchResult
function window_matching.match_records_to_reopened_windows(records, live_windows)
    return match_by_criteria({ has_same_document, has_same_title }, records, live_windows)
end

---Matches the records to the windows of applications that the tool has just launched.
---The windows have new ids, so the title decides first and the application last.
---@param records WindowRecord[]
---@param live_windows LiveWindow[]
---@return WindowMatchResult
function window_matching.match_records_to_launched_windows(records, live_windows)
    return match_by_criteria({ has_same_title, has_same_application }, records, live_windows)
end

return window_matching
