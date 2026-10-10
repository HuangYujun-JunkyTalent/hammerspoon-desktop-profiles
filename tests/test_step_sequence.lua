local expect = require("tests.expect")
local step_sequence = require("desktop_manager.core.step_sequence")

---@param callback fun()
local function run_now(callback)
    callback()
end

return {
    steps_run_in_order = function()
        local visited = {}
        local finished_with = "not finished"
        step_sequence.run(
            {
                function(continue)
                    table.insert(visited, "first")
                    continue()
                end,
                function(continue)
                    table.insert(visited, "second")
                    continue()
                end,
            },
            run_now,
            function(error_message)
                finished_with = error_message
            end
        )
        expect.equal(visited, { "first", "second" })
        expect.equal(finished_with, nil)
    end,

    a_failing_step_stops_the_sequence = function()
        local visited = {}
        local finished_with = nil
        step_sequence.run(
            {
                function()
                    error("the window is gone", 0)
                end,
                function(continue)
                    table.insert(visited, "second")
                    continue()
                end,
            },
            run_now,
            function(error_message)
                finished_with = error_message
            end
        )
        expect.equal(visited, {})
        expect.equal(finished_with, "step 1 failed: the window is gone")
    end,

    a_step_may_continue_later = function()
        local pending = {}
        local is_finished = false
        step_sequence.run(
            {
                function(continue)
                    table.insert(pending, continue)
                end,
            },
            run_now,
            function()
                is_finished = true
            end
        )
        expect.equal(is_finished, false)
        pending[1]()
        expect.equal(is_finished, true)
    end,
}
