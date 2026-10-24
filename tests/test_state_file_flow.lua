local controller_world = require("tests.controller_world")
local expect = require("tests.expect")

return {
    an_unreadable_state_file_that_cannot_be_moved_is_reported_as_not_moved = function()
        local world, controller = controller_world.start_world(nil, { format_version = 99 })
        local warning = expect.present(world.notifications[1], "the warning of the state file")
        local moved_to, rename_error = warning:match(
            "^the saved state has format version 99, and this version reads %d+ to %d+,"
                .. " and the move to (/fake/state%.json%.unreadable%-%d+%-%d+) failed with"
                .. ' "(.*)", so a new state started and the next save replaces the file$'
        )
        expect.present(moved_to, "the path of the move in " .. warning)
        expect.equal(rename_error, "No such file or directory")
        expect.equal(world.log_lines[#world.log_lines], warning)
        expect.equal(controller.state.active_profile_number, nil)
    end,
}
