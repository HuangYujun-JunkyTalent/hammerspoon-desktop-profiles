local concealment_method = require("desktop_manager.core.concealment_method")

local profile_switch = {}

---An open window at the time of a switch.
---@class OpenWindow
---@field window_id integer
---@field bundle_id string
---@field is_minimized boolean
---@field is_app_hidden boolean

---An open window and whether the profile entered keeps it in sight.
---@class SwitchCandidate
---@field window_id integer
---@field bundle_id string
---@field is_in_sight boolean
---@field is_kept boolean

---@class ConcealmentPlan
---@field bundle_ids_to_hide string[]
---@field window_ids_to_minimize integer[]

---The profile entered keeps in sight the windows it recorded in sight.
---It also keeps a window that no profile recorded, such as a window opened while no profile was
---active, so that the window joins the profile at its next capture.
---Every other window goes out of sight: the profile entered recorded it out of sight, or another
---profile recorded it and the profile entered did not.
---@param open_windows OpenWindow[]
---@param matches WindowMatch[] the records of the profile entered, matched to the open windows
---@param recorded table<integer, table<string, boolean>> the windows that some profile recorded
---@return SwitchCandidate[]
function profile_switch.mark_kept_windows(open_windows, matches, recorded)
    local record_by_window_id = {}
    for _, match in ipairs(matches) do
        record_by_window_id[match.window_id] = match.record
    end
    local candidates = {}
    for _, window in ipairs(open_windows) do
        local record = record_by_window_id[window.window_id]
        local is_recorded = recorded[window.window_id] ~= nil
            and recorded[window.window_id][window.bundle_id] == true
        local is_kept
        if record then
            is_kept = not record.is_out_of_sight
        else
            is_kept = not is_recorded
        end
        table.insert(candidates, {
            window_id = window.window_id,
            bundle_id = window.bundle_id,
            is_in_sight = not window.is_minimized and not window.is_app_hidden,
            is_kept = is_kept,
        })
    end
    return candidates
end

---@param candidates SwitchCandidate[]
---@return table<string, SwitchCandidate[]>
---@return string[] bundle_ids in the order of first appearance
local function group_by_bundle(candidates)
    local groups, bundle_ids = {}, {}
    for _, candidate in ipairs(candidates) do
        if not groups[candidate.bundle_id] then
            groups[candidate.bundle_id] = {}
            table.insert(bundle_ids, candidate.bundle_id)
        end
        table.insert(groups[candidate.bundle_id], candidate)
    end
    return groups, bundle_ids
end

---@param candidates SwitchCandidate[]
---@return ConcealmentPlan
local function plan_minimizing(candidates)
    local plan = { bundle_ids_to_hide = {}, window_ids_to_minimize = {} }
    for _, candidate in ipairs(candidates) do
        if candidate.is_in_sight and not candidate.is_kept then
            table.insert(plan.window_ids_to_minimize, candidate.window_id)
        end
    end
    return plan
end

---@param candidates SwitchCandidate[]
---@return ConcealmentPlan
local function plan_hiding(candidates)
    local groups, bundle_ids = group_by_bundle(candidates)
    local plan = { bundle_ids_to_hide = {}, window_ids_to_minimize = {} }
    for _, bundle_id in ipairs(bundle_ids) do
        local has_kept_window, in_sight_to_conceal = false, {}
        for _, candidate in ipairs(groups[bundle_id]) do
            if candidate.is_kept then
                has_kept_window = true
            elseif candidate.is_in_sight then
                table.insert(in_sight_to_conceal, candidate)
            end
        end
        if not has_kept_window and #in_sight_to_conceal > 0 then
            table.insert(plan.bundle_ids_to_hide, bundle_id)
        else
            for _, candidate in ipairs(in_sight_to_conceal) do
                table.insert(plan.window_ids_to_minimize, candidate.window_id)
            end
        end
    end
    return plan
end

local PLANNERS = {
    [concealment_method.MINIMIZE_WINDOWS] = plan_minimizing,
    [concealment_method.HIDE_APPLICATIONS] = plan_hiding,
}

---Plans how to take out of sight the windows that the profile entered does not keep.
---A window already out of sight needs nothing.
---@param method string a value of concealment_method
---@param candidates SwitchCandidate[]
---@return ConcealmentPlan
function profile_switch.plan_concealment(method, candidates)
    local planner = PLANNERS[method]
    if not planner then
        error(string.format("unknown concealment method %q", tostring(method)), 2)
    end
    return planner(candidates)
end

return profile_switch
