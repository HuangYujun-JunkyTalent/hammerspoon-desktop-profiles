local expect = require("tests.expect")
local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")

return {
    is_valid_accepts_the_three_choices_alone = function()
        expect.equal(
            hidden_application_windows.is_valid(hidden_application_windows.LEAVE_OUT),
            true
        )
        expect.equal(
            hidden_application_windows.is_valid(hidden_application_windows.LIST_WHERE_FOUND),
            true
        )
        expect.equal(hidden_application_windows.is_valid(hidden_application_windows.LIST_ALL), true)
        expect.equal(hidden_application_windows.is_valid("show_some"), false)
        expect.equal(hidden_application_windows.is_valid(nil), false)
    end,
}
