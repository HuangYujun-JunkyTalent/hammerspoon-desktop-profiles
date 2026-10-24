local track_windows = require("desktop_manager.macos.track_windows")

local conceal_windows = {}

---@param plan ConcealmentPlan
---@param window_by_id table<integer, table> the hs.window of each window id
---@return string[] failures
function conceal_windows.apply(plan, window_by_id)
    local failures = {}
    local applications = track_windows.list_running_applications(plan.bundle_ids_to_hide)
    for _, application in ipairs(applications) do
        application:hide()
    end
    for _, window_id in ipairs(plan.window_ids_to_minimize) do
        local window = window_by_id[window_id]
        if window then
            window:minimize()
        else
            table.insert(failures, string.format("window %d was not found to minimize", window_id))
        end
    end
    return failures
end

return conceal_windows
