local locate_desktops = require("desktop_manager.core.locate_desktops")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local profile_switch = require("desktop_manager.core.profile_switch")
local unit_frames = require("desktop_manager.core.unit_frames")
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
    local location = locate_desktops.locate_space(desktop_layout, window.space_id)
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
        and unit_frames.from_unit_frame(record.unit_frame, location.screen.screen_frame)
    return recorded_frame ~= nil
        and not window_routes.are_frames_close(window.frame, recorded_frame)
end

---The unreached windows whose record the restore would carry out: a record in sight whose desktop
---or frame differs from the place where the window server lists the window.
---A record on a desktop beyond the desktops of its screen counts, because the restore adds that
---desktop and moves the window there.
---@param unreached ServerWindow[]
---@param matches WindowMatch[] the records matched to the known and the unreached windows
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

---The unreached windows that the switch takes out of sight.
---Under the method that hides applications, an application without a kept window is hidden whole,
---which takes its unreached windows out of sight without a reach.
---@param method string a value of concealment_method
---@param unreached ServerWindow[]
---@param candidates SwitchCandidate[] the known and the unreached windows, marked by the switch
---@return integer[] window ids, in the order of the unreached windows
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

---The moves that bring unreached windows into view, on the desktop that their screens show.
---@class MovesIntoView
---@field moves WindowMove[] in the order of the windows
---@field desktop_numbers table<integer, integer> the desktop of each moved window before its move
---@field windows_without_shown_desktop ServerWindow[] the windows whose screen shows no desktop,
---in their order

---@param windows ServerWindow[]
---@param desktop_layout DesktopLayout
---@return MovesIntoView
function reach_plan.plan_moves_into_view(windows, desktop_layout)
    local plan = { moves = {}, desktop_numbers = {}, windows_without_shown_desktop = {} }
    for _, window in ipairs(windows) do
        local location = locate_desktops.locate_space(desktop_layout, window.space_id)
        local shown_desktop_number = location
            and locate_desktops.find_shown_desktop_number(location.screen)
        local view_space_id = location
            and shown_desktop_number
            and location.screen.space_ids[shown_desktop_number]
        if location and view_space_id then
            plan.desktop_numbers[window.window_id] = location.desktop_number
            table.insert(plan.moves, { window_id = window.window_id, space_id = view_space_id })
        else
            table.insert(plan.windows_without_shown_desktop, window)
        end
    end
    return plan
end

---@param windows ServerWindow[]
---@param window_ids integer[]
---@return ServerWindow[] the windows of the ids, each once, in the order of the windows
function reach_plan.keep_windows_of_ids(windows, window_ids)
    local is_chosen, kept = {}, {}
    for _, window_id in ipairs(window_ids) do
        is_chosen[window_id] = true
    end
    for _, window in ipairs(windows) do
        if is_chosen[window.window_id] then
            table.insert(kept, window)
        end
    end
    return kept
end

return reach_plan
