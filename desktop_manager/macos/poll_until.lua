local retained_timers = require("desktop_manager.macos.retained_timers")

local poll_until = {}

---@param is_met fun(): boolean
---@return boolean
local function check_safely(is_met)
    local is_successful, result = pcall(is_met)
    return is_successful and result == true
end

---Calls `on_done(true)` once `is_met` returns true, or `on_done(false)` after the timeout.
---@param is_met fun(): boolean
---@param timeout_seconds number
---@param interval_seconds number
---@param on_done fun(is_met: boolean)
function poll_until.wait(is_met, timeout_seconds, interval_seconds, on_done)
    if check_safely(is_met) then
        on_done(true)
        return
    end
    local deadline = hs.timer.secondsSinceEpoch() + timeout_seconds
    local timer
    timer = retained_timers.every(interval_seconds, function()
        local has_met = check_safely(is_met)
        if has_met or hs.timer.secondsSinceEpoch() >= deadline then
            retained_timers.stop(timer)
            on_done(has_met)
        end
    end)
end

---Calls `on_done(value)` once `find` returns a value, or `on_done(nil)` after the timeout.
---@generic T
---@param find fun(): T|nil
---@param timeout_seconds number
---@param interval_seconds number
---@param on_done fun(value: T|nil) the value that `find` returned, or nil after the timeout
function poll_until.wait_for_value(find, timeout_seconds, interval_seconds, on_done)
    local found = nil
    poll_until.wait(
        function()
            found = find()
            return found ~= nil
        end,
        timeout_seconds,
        interval_seconds,
        function()
            on_done(found)
        end
    )
end

return poll_until
