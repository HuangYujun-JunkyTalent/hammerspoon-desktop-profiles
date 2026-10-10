local expect = require("tests.expect")
local url_command = require("desktop_manager.core.url_command")

return {
    activate_reads_the_profile_number = function()
        local command = url_command.parse({ action = "activate", profile = "3" }, 9)
        expect.equal(command, { action = "activate", profile_number = 3 })
    end,

    deactivate_needs_no_profile = function()
        expect.equal(url_command.parse({ action = "deactivate" }, 9), { action = "deactivate" })
    end,

    rename_trims_the_name = function()
        local command =
            url_command.parse({ action = "rename", profile = "2", name = "  Writing " }, 9)
        expect.equal(command, { action = "rename", profile_number = 2, name = "Writing" })
    end,

    rename_rejects_a_blank_name = function()
        local command, message =
            url_command.parse({ action = "rename", profile = "2", name = " " }, 9)
        expect.equal(command, nil)
        expect.equal(message, "the rename action has no name parameter with a visible character")
    end,

    a_profile_out_of_range_is_rejected = function()
        local command, message = url_command.parse({ action = "toggle", profile = "12" }, 9)
        expect.equal(command, nil)
        expect.equal(message, 'the profile "12" is not a number from 1 to 9')
    end,

    an_unknown_action_is_rejected = function()
        local _, message = url_command.parse({ action = "explode" }, 9)
        expect.equal(message, 'the action "explode" is unknown')
    end,

    a_missing_action_is_rejected = function()
        local _, message = url_command.parse({}, 9)
        expect.equal(message, "the URL has no action parameter")
    end,
}
