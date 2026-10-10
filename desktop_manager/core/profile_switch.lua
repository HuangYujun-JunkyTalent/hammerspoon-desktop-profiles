local profile_switch = {}

---@class OwnedWindow
---@field window_id integer
---@field bundle_id string
---@field owner_number integer|nil
---@field is_minimized boolean

---@class ConcealmentPlan
---@field bundle_ids_to_hide string[]
---@field window_ids_to_minimize integer[]

---@param live_windows OwnedWindow[]
---@return table<string, OwnedWindow[]>
---@return string[] bundle_ids in the order of first appearance
local function group_by_bundle(live_windows)
    local groups, bundle_ids = {}, {}
    for _, window in ipairs(live_windows) do
        if not groups[window.bundle_id] then
            groups[window.bundle_id] = {}
            table.insert(bundle_ids, window.bundle_id)
        end
        table.insert(groups[window.bundle_id], window)
    end
    return groups, bundle_ids
end

---Plans how to take the windows of the other profiles out of sight when one profile becomes active.
---An application whose windows all belong to other profiles is hidden.
---In any other application, those windows are minimized.
---@param live_windows OwnedWindow[]
---@param kept_profile_number integer
---@return ConcealmentPlan
function profile_switch.plan_concealment(live_windows, kept_profile_number)
    local groups, bundle_ids = group_by_bundle(live_windows)
    local plan = { bundle_ids_to_hide = {}, window_ids_to_minimize = {} }
    for _, bundle_id in ipairs(bundle_ids) do
        local concealed = {}
        for _, window in ipairs(groups[bundle_id]) do
            if window.owner_number ~= nil and window.owner_number ~= kept_profile_number then
                table.insert(concealed, window)
            end
        end
        if #concealed > 0 and #concealed == #groups[bundle_id] then
            table.insert(plan.bundle_ids_to_hide, bundle_id)
        else
            for _, window in ipairs(concealed) do
                if not window.is_minimized then
                    table.insert(plan.window_ids_to_minimize, window.window_id)
                end
            end
        end
    end
    return plan
end

---@param live_windows OwnedWindow[]
---@return integer[]
function profile_switch.find_unowned_window_ids(live_windows)
    local window_ids = {}
    for _, window in ipairs(live_windows) do
        if window.owner_number == nil then
            table.insert(window_ids, window.window_id)
        end
    end
    return window_ids
end

return profile_switch
