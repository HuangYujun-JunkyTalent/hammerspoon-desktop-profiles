local retained_timers = require("desktop_manager.macos.retained_timers")

local work_watchdog = {}

---Numbers the switches, the restores and the presses in Mission Control, and stops the one that
---runs when it has not ended after `busy_watchdog_seconds`, as after an error in a timer of a step.
---A stop raises the number, so that the later steps of the stopped work end nothing.
---@class WorkWatchdog
---@field timing Timing
---@field on_stop fun() ends the stopped work, once its later steps act no further
---@field number integer the number of the last work, which a stop changes
---@field timer table|nil an hs.timer
local WorkWatchdog = {}
WorkWatchdog.__index = WorkWatchdog

---@param timing Timing whose `busy_watchdog_seconds` each start reads
---@param on_stop fun()
---@return WorkWatchdog
function work_watchdog.new(timing, on_stop)
    return setmetatable({ timing = timing, on_stop = on_stop, number = 0 }, WorkWatchdog)
end

---@return integer the number of the work, which `stop` takes
function WorkWatchdog:start()
    self.number = self.number + 1
    retained_timers.stop(self.timer)
    self.timer = retained_timers.after(self.timing.busy_watchdog_seconds, function()
        self.timer = nil
        self.number = self.number + 1
        self.on_stop()
    end)
    return self.number
end

---@return fun(): boolean whether the switch, the restore or the press that runs now still runs, and
---the watchdog has not stopped it
function WorkWatchdog:watch_current()
    local number = self.number
    return function()
        return number == self.number
    end
end

---Wraps a callback of a step of the work that runs now, so that the callback does nothing once the
---watchdog has stopped that work.
---@generic F: function
---@param callback F
---@return F
function WorkWatchdog:continue(callback)
    local is_current = self:watch_current()
    return function(...)
        if is_current() then
            callback(...)
        end
    end
end

---@param number integer
---@return boolean whether the work still runs, and the watchdog has not stopped it
function WorkWatchdog:stop(number)
    if number ~= self.number then
        return false
    end
    retained_timers.stop(self.timer)
    self.timer = nil
    return true
end

return work_watchdog
