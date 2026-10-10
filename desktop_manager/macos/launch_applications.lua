local poll_until = require("desktop_manager.macos.poll_until")
local retained_timers = require("desktop_manager.macos.retained_timers")

local launch_applications = {}

local WINDOW_POLL_SECONDS = 0.25

---@param bundle_id string
---@return boolean
local function has_window(bundle_id)
    local application = hs.application.get(bundle_id)
    return application ~= nil and #application:allWindows() > 0
end

---Launches the applications, and calls `on_done` once each shows a window or the timeout ends.
---@param bundle_ids string[]
---@param timing Timing
---@param on_done fun()
function launch_applications.launch_and_wait(bundle_ids, timing, on_done)
    for _, bundle_id in ipairs(bundle_ids) do
        hs.application.open(bundle_id)
    end
    poll_until.wait(
        function()
            for _, bundle_id in ipairs(bundle_ids) do
                if not has_window(bundle_id) then
                    return false
                end
            end
            return true
        end,
        timing.application_launch_timeout_seconds,
        WINDOW_POLL_SECONDS,
        function()
            retained_timers.after(timing.window_settle_seconds, on_done)
        end
    )
end

return launch_applications
