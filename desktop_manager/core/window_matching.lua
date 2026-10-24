local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")

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

---@class WindowMatch
---@field record WindowRecord
---@field window_id integer

---@class WindowMatchResult
---@field matches WindowMatch[]
---@field unmatched_records WindowRecord[]

---@alias MatchCriterion fun(record: WindowRecord, window: OpenWindow): boolean

---@type MatchCriterion
local function has_same_id(record, window)
    return record.window_id == window.window_id and record.bundle_id == window.bundle_id
end

---@type MatchCriterion
local function has_same_title(record, window)
    return record.bundle_id == window.bundle_id and record.title == window.title
end

---A record without a title, such as the record of a window that the window server listed without
---the permission for Screen Recording, matches no window by its title.
---@type MatchCriterion
local function has_same_given_title(record, window)
    return record.title ~= "" and has_same_title(record, window)
end

---@type MatchCriterion
local function has_same_id_and_title(record, window)
    return has_same_id(record, window) and record.title == window.title
end

---Pairs each saved record with at most one open window, and each window with at most one record,
---trying the criteria in order.
---@param criteria MatchCriterion[]
---@param records WindowRecord[]
---@param open_windows OpenWindow[]
---@return WindowMatchResult
local function match_by_criteria(criteria, records, open_windows)
    local used_window_ids = {}
    local window_id_by_record_index = {}
    for _, criterion in ipairs(criteria) do
        for record_index, record in ipairs(records) do
            if not window_id_by_record_index[record_index] then
                for _, window in ipairs(open_windows) do
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

local CRITERIA_BY_ID = {
    [missing_window_policy.MATCH_ID_ALONE] = { has_same_id },
    [missing_window_policy.MATCH_TITLE] = { has_same_id, has_same_title },
}

local CRITERIA_BY_TITLE = { has_same_id_and_title, has_same_given_title, has_same_id }

---Matches the records to the windows that are open at a switch.
---Under `match_windows_by.ID`, a window keeps its id while it stays open, so the id decides first,
---and under the policy that matches titles a window with the same title takes a record whose window
---no longer exists.
---Under `match_windows_by.TITLE`, the title decides first, and the policy plays no part in this
---match.
---Under both ways, the policy also decides whether the controller gives the records of a closed
---window to a reopened window before the match.
---A record that no window takes stays unmatched, and `unmatched_window_action` alone decides
---whether a new window opens for it.
---@param match_key string a value of match_windows_by
---@param policy string a value of missing_window_policy
---@param records WindowRecord[]
---@param open_windows OpenWindow[]
---@return WindowMatchResult
function window_matching.match_records_to_open_windows(match_key, policy, records, open_windows)
    local criteria
    if match_key == match_windows_by.TITLE then
        criteria = CRITERIA_BY_TITLE
    elseif match_key == match_windows_by.ID then
        criteria = CRITERIA_BY_ID[policy]
        if not criteria then
            error(string.format("unknown missing window policy %q", tostring(policy)), 2)
        end
    else
        error(string.format("unknown way to match windows %q", tostring(match_key)), 2)
    end
    return match_by_criteria(criteria, records, open_windows)
end

---The records of windows that no longer exist, each window once per application, in the order of
---the records.
---`is_gone` reads macOS, so it runs only for a record with a window id that no open window has and
---that is not listed yet.
---@param records WindowRecord[]
---@param is_open fun(window_id: integer): boolean
---@param is_gone fun(window_id: integer): boolean
---@return WindowRecord[]
function window_matching.list_closed_records(records, is_open, is_gone)
    local closed_records, is_listed = {}, {}
    for _, record in ipairs(records) do
        local window_id = record.window_id
        if
            window_id
            and not (is_listed[window_id] and is_listed[window_id][record.bundle_id])
            and not is_open(window_id)
            and is_gone(window_id)
        then
            is_listed[window_id] = is_listed[window_id] or {}
            is_listed[window_id][record.bundle_id] = true
            table.insert(closed_records, record)
        end
    end
    return closed_records
end

---Matches the records of windows that no longer exist to open windows that no profile recorded.
---macOS gives a window that its application reopens a new id, so the title decides.
---The place is left out, because macOS opens a new window at the place of the last closed one.
---@param records WindowRecord[]
---@param open_windows OpenWindow[]
---@return WindowMatchResult
function window_matching.match_records_to_reopened_windows(records, open_windows)
    return match_by_criteria({ has_same_title }, records, open_windows)
end

return window_matching
