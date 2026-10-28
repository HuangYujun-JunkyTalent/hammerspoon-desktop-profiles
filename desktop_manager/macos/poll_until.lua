local retained_timers = require("desktop_manager.macos.retained_timers")

local poll_until = {}

---@param is_met fun(): boolean
---@return boolean
local function check_safely(is_met)
    local is_successful, result = pcall(is_met)
    return is_successful and result == true
end

---Calls `on_done(true)` once `is_met` returns true, or `on_done(false)` after the timeout.
---A check that comes later than the interval after the end of the previous check, as when another
---call blocked Hammerspoon, moves the deadline on by the delay, so that the wait checks as often as
---it would without the block.
---The time of a check itself counts against the wait, which starts after the first check, so a
---check that stays slow, as a call to an application that does not answer, ends the wait at most
---one interval and one check after the timeout.
---On 2026-10-28, under a load of about 23 on 8 cores, blocks of up to a second took the whole wait
---for a window of Activity Monitor to come in reach, which then went back to its desktop.
---@param is_met fun(): boolean
---@param timeout_seconds number
---@param interval_seconds number
---@param on_done fun(is_met: boolean)
function poll_until.wait(is_met, timeout_seconds, interval_seconds, on_done)
    if check_safely(is_met) then
        on_done(true)
        return
    end
    local checked_at = hs.timer.secondsSinceEpoch()
    local deadline = checked_at + timeout_seconds
    local timer
    timer = retained_timers.every(interval_seconds, function()
        deadline = deadline
            + math.max(0, hs.timer.secondsSinceEpoch() - checked_at - interval_seconds)
        local has_met = check_safely(is_met)
        checked_at = hs.timer.secondsSinceEpoch()
        if has_met or checked_at >= deadline then
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
