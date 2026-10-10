local step_sequence = {}

---A step does its work and then calls `continue` once, possibly later from a timer.
---@alias Step fun(continue: fun())

---Defers a function to a later turn of the event loop, so that the stack stays short.
---@alias Scheduler fun(callback: fun())

---Runs the steps one after another.
---`on_finished` receives nil after the last step, or the error message of the step that raised one.
---@param steps Step[]
---@param schedule Scheduler
---@param on_finished fun(error_message: string|nil)
function step_sequence.run(steps, schedule, on_finished)
    local next_index = 1
    local function run_next_step()
        local step = steps[next_index]
        if step == nil then
            on_finished(nil)
            return
        end
        local step_index = next_index
        next_index = next_index + 1
        local has_continued = false
        local function continue()
            if has_continued then
                error(string.format("step %d called continue more than once", step_index), 2)
            end
            has_continued = true
            schedule(run_next_step)
        end
        local is_successful, error_message = pcall(step, continue)
        if not is_successful then
            on_finished(string.format("step %d failed: %s", step_index, tostring(error_message)))
        end
    end
    schedule(run_next_step)
end

return step_sequence
