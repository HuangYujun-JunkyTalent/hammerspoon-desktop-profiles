---Hammerspoon stops a timer that Lua garbage-collects, so running timers are kept in a table here.
local retained_timers = {}

local running = {}

---@param seconds number
---@param callback fun()
---@return table timer an hs.timer
function retained_timers.after(seconds, callback)
    local timer
    timer = hs.timer.doAfter(seconds, function()
        running[timer] = nil
        callback()
    end)
    running[timer] = true
    return timer
end

---@param seconds number
---@param callback fun()
---@return table timer an hs.timer
function retained_timers.every(seconds, callback)
    local timer = hs.timer.doEvery(seconds, callback)
    running[timer] = true
    return timer
end

---@param timer table|nil an hs.timer
function retained_timers.stop(timer)
    if timer then
        timer:stop()
        running[timer] = nil
    end
end

---@return integer
function retained_timers.count_running()
    local count = 0
    for _ in pairs(running) do
        count = count + 1
    end
    return count
end

---@param callback fun()
function retained_timers.defer(callback)
    retained_timers.after(0, callback)
end

return retained_timers
