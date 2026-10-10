local expect = require("tests.expect")
local profile_switch = require("desktop_manager.core.profile_switch")

return {
    an_application_whose_windows_all_belong_to_other_profiles_is_hidden = function()
        local plan = profile_switch.plan_concealment({
            {
                window_id = 1,
                bundle_id = "com.microsoft.Word",
                owner_number = 1,
                is_minimized = false,
            },
            {
                window_id = 2,
                bundle_id = "com.microsoft.Word",
                owner_number = 3,
                is_minimized = false,
            },
        }, 2)
        expect.equal(
            plan,
            { bundle_ids_to_hide = { "com.microsoft.Word" }, window_ids_to_minimize = {} }
        )
    end,

    a_shared_application_has_only_the_other_windows_minimized = function()
        local plan = profile_switch.plan_concealment({
            {
                window_id = 1,
                bundle_id = "com.apple.Safari",
                owner_number = 1,
                is_minimized = false,
            },
            {
                window_id = 2,
                bundle_id = "com.apple.Safari",
                owner_number = 2,
                is_minimized = false,
            },
            {
                window_id = 3,
                bundle_id = "com.apple.Safari",
                owner_number = 1,
                is_minimized = true,
            },
        }, 2)
        expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = { 1 } })
    end,

    unowned_windows_stay_visible = function()
        local plan = profile_switch.plan_concealment({
            {
                window_id = 1,
                bundle_id = "com.apple.Notes",
                owner_number = nil,
                is_minimized = false,
            },
        }, 2)
        expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = {} })
        expect.equal(
            profile_switch.find_unowned_window_ids({
                {
                    window_id = 1,
                    bundle_id = "com.apple.Notes",
                    owner_number = nil,
                    is_minimized = false,
                },
                {
                    window_id = 2,
                    bundle_id = "com.apple.Notes",
                    owner_number = 2,
                    is_minimized = false,
                },
            }),
            { 1 }
        )
    end,
}
