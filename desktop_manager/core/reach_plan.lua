local arrangement_capture = require("desktop_manager.core.arrangement_capture")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local profile_switch = require("desktop_manager.core.profile_switch")
local window_routes = require("desktop_manager.core.window_routes")

---Chooses the windows that accessibility does not reach and that a switch or a restore acts on.
---Such a window comes into view by a move by its id before the switch, so that Hammerspoon can set
---its frame or minimize it, and it shows on the desktop in view for a moment.
---A window that the switch leaves where it is therefore stays unreached.
local reach_plan = {}

---@param windows ServerWindow[]
---@return table<integer, ServerWindow>
local function index_by_window_id(windows)
    local index = {}
    for _, window in ipairs(windows) do
        index[window.window_id] = window
    end
    return index
end

---@param record WindowRecord
---@param window ServerWindow
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return boolean whether the restore would move the window or set its frame
local function is_misplaced(record, window, configuration, desktop_layout)
    local slot = monitor_configuration.find_slot(configuration, record.slot_key)
    local location = arrangement_capture.locate_space(desktop_layout, window.space_id)
    if not slot or not location then
        return false
    end
    if
        location.screen.screen_uuid ~= slot.screen_uuid
        or location.desktop_number ~= record.desktop_number
    then
        return true
    end
    local recorded_frame = record.unit_frame
        and arrangement_capture.from_unit_frame(record.unit_frame, location.screen.screen_frame)
    return recorded_frame ~= nil
        and not window_routes.are_frames_close(window.frame, recorded_frame)
end

---The unseen windows whose record the restore would carry out: a record in sight whose desktop or
---frame differs from the place where the window server lists the window.
---A record on a desktop beyond the desktops of its screen counts, because the restore adds that
---desktop and moves the window there.
---@param unreached ServerWindow[]
---@param matches WindowMatch[] the records matched to the known and the unseen windows
---@param configuration MonitorConfiguration
---@param desktop_layout DesktopLayout
---@return integer[] window ids, in the order of the matches
function reach_plan.select_misplaced(unreached, matches, configuration, desktop_layout)
    local unreached_by_id = index_by_window_id(unreached)
    local window_ids = {}
    for _, match in ipairs(matches) do
        local window, record = unreached_by_id[match.window_id], match.record
        if
            window
            and not record.is_out_of_sight
            and record.slot_key
            and record.desktop_number
            and is_misplaced(record, window, configuration, desktop_layout)
        then
            table.insert(window_ids, match.window_id)
        end
    end
    return window_ids
end

---The unseen windows that the switch takes out of sight.
---Under the method that hides applications, an application without a kept window is hidden whole,
---which takes its unseen windows out of sight without a reach.
---@param method string a value of concealment_method
---@param unreached ServerWindow[]
---@param candidates SwitchCandidate[] the known and the unseen windows, marked by the switch
---@return integer[] window ids, in the order of the unseen windows
function reach_plan.select_concealed(method, unreached, candidates)
    local candidate_by_id, is_hidden_whole = {}, {}
    for _, candidate in ipairs(candidates) do
        candidate_by_id[candidate.window_id] = candidate
    end
    for _, bundle_id in
        ipairs(profile_switch.plan_concealment(method, candidates).bundle_ids_to_hide)
    do
        is_hidden_whole[bundle_id] = true
    end
    local window_ids = {}
    for _, window in ipairs(unreached) do
        local candidate = candidate_by_id[window.window_id]
        if candidate and not candidate.is_kept and not is_hidden_whole[window.bundle_id] then
            table.insert(window_ids, window.window_id)
        end
    end
    return window_ids
end

return reach_plan
