local expect = require("tests.expect")
local url_command = require("desktop_manager.core.url_command")

local LIMITS = { profile_count = 9, app_number_count = 9 }

return {
    activate_reads_the_profile_number = function()
        local command = url_command.parse({ action = "activate", profile = "3" }, LIMITS)
        expect.equal(command, { action = "activate", profile_number = 3 })
    end,

    deactivate_needs_no_profile = function()
        expect.equal(
            url_command.parse({ action = "deactivate" }, LIMITS),
            { action = "deactivate" }
        )
    end,

    deactivate_may_name_a_profile = function()
        local command = url_command.parse({ action = "deactivate", profile = "4" }, LIMITS)
        expect.equal(command, { action = "deactivate", profile_number = 4 })
        local rejected, message =
            url_command.parse({ action = "deactivate", profile = "0" }, LIMITS)
        expect.equal(rejected, nil)
        expect.equal(message, 'the profile "0" is not a number from 1 to 9')
    end,

    rename_trims_the_name = function()
        local command =
            url_command.parse({ action = "rename", profile = "2", name = "  Writing " }, LIMITS)
        expect.equal(command, { action = "rename", profile_number = 2, name = "Writing" })
    end,

    rename_rejects_a_blank_name = function()
        local command, message =
            url_command.parse({ action = "rename", profile = "2", name = " " }, LIMITS)
        expect.equal(command, nil)
        expect.equal(message, "the rename action has no name parameter with a visible character")
    end,

    a_profile_out_of_range_is_rejected = function()
        local command, message = url_command.parse({ action = "toggle", profile = "12" }, LIMITS)
        expect.equal(command, nil)
        expect.equal(message, 'the profile "12" is not a number from 1 to 9')
    end,

    an_unknown_action_is_rejected = function()
        local _, message = url_command.parse({ action = "explode" }, LIMITS)
        expect.equal(message, 'the action "explode" is unknown')
    end,

    a_missing_action_is_rejected = function()
        local _, message = url_command.parse({}, LIMITS)
        expect.equal(message, "the URL has no action parameter")
    end,

    number_app_reads_the_number_and_the_application = function()
        local command =
            url_command.parse({ action = "number-app", number = "3", app = " Firefox " }, LIMITS)
        expect.equal(command, { action = "number-app", app_number = 3, app = "Firefox" })
        local released = url_command.parse({ action = "release-app-number", number = "3" }, LIMITS)
        expect.equal(released, { action = "release-app-number", app_number = 3 })
    end,

    number_app_rejects_a_missing_application_and_a_number_out_of_range = function()
        local missing, missing_message =
            url_command.parse({ action = "number-app", number = "3" }, LIMITS)
        expect.equal(missing, nil)
        expect.equal(
            missing_message,
            "the number-app action has no app parameter with a visible character"
        )
        local _, range_message =
            url_command.parse({ action = "number-app", number = "10", app = "Firefox" }, LIMITS)
        expect.equal(range_message, 'the app number "10" is not a number from 1 to 9')
    end,
}
