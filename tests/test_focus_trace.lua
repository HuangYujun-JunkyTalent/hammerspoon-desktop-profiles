local expect = require("tests.expect")
local focus_trace = require("desktop_manager.macos.focus_trace")

return {
    a_mark_builds_no_text_while_the_trace_is_off = function()
        local built = 0
        local function describe()
            built = built + 1
            return "text"
        end
        expect.equal(focus_trace.is_running(), false)
        focus_trace.mark(describe)
        focus_trace.mark_and_watch(describe)
        expect.equal(built, 0)
    end,
}
