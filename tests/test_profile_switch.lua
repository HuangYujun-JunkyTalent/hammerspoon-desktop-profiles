local concealment_method = require("desktop_manager.core.concealment_method")
local expect = require("tests.expect")
local profile_switch = require("desktop_manager.core.profile_switch")

local WORD_OF_PROFILES_1_AND_3 = {
    {
        window_id = 1,
        bundle_id = "com.microsoft.Word",
        holder_numbers = { 1 },
        is_minimized = false,
    },
    {
        window_id = 2,
        bundle_id = "com.microsoft.Word",
        holder_numbers = { 3 },
        is_minimized = false,
    },
}

local SAFARI_OF_PROFILES_1_AND_2 = {
    {
        window_id = 1,
        bundle_id = "com.apple.Safari",
        holder_numbers = { 1 },
        is_minimized = false,
    },
    {
        window_id = 2,
        bundle_id = "com.apple.Safari",
        holder_numbers = { 2 },
        is_minimized = false,
    },
    {
        window_id = 3,
        bundle_id = "com.apple.Safari",
        holder_numbers = { 1 },
        is_minimized = true,
    },
}

local UNOWNED_NOTES = {
    {
        window_id = 1,
        bundle_id = "com.apple.Notes",
        holder_numbers = {},
        is_minimized = false,
    },
}

return {
    minimizing_takes_every_window_of_the_other_profiles = function()
        local plan = profile_switch.plan_concealment(
            concealment_method.MINIMIZE_WINDOWS,
            WORD_OF_PROFILES_1_AND_3,
            2
        )
        expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = { 1, 2 } })
    end,

    minimizing_leaves_the_minimized_windows_and_those_of_the_kept_profile = function()
        local plan = profile_switch.plan_concealment(
            concealment_method.MINIMIZE_WINDOWS,
            SAFARI_OF_PROFILES_1_AND_2,
            2
        )
        expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = { 1 } })
    end,

    hiding_takes_an_application_whose_windows_all_belong_to_other_profiles = function()
        local plan = profile_switch.plan_concealment(
            concealment_method.HIDE_APPLICATIONS,
            WORD_OF_PROFILES_1_AND_3,
            2
        )
        expect.equal(
            plan,
            { bundle_ids_to_hide = { "com.microsoft.Word" }, window_ids_to_minimize = {} }
        )
    end,

    hiding_minimizes_the_other_windows_of_a_shared_application = function()
        local plan = profile_switch.plan_concealment(
            concealment_method.HIDE_APPLICATIONS,
            SAFARI_OF_PROFILES_1_AND_2,
            2
        )
        expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = { 1 } })
    end,

    a_window_that_the_kept_profile_also_holds_stays = function()
        local shared = {
            {
                window_id = 7,
                bundle_id = "org.mozilla.firefox",
                holder_numbers = { 1, 2 },
                is_minimized = false,
            },
        }
        for _, method in ipairs({
            concealment_method.MINIMIZE_WINDOWS,
            concealment_method.HIDE_APPLICATIONS,
        }) do
            local plan = profile_switch.plan_concealment(method, shared, 2)
            expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = {} })
        end
    end,

    unowned_windows_stay_visible = function()
        for _, method in ipairs({
            concealment_method.MINIMIZE_WINDOWS,
            concealment_method.HIDE_APPLICATIONS,
        }) do
            local plan = profile_switch.plan_concealment(method, UNOWNED_NOTES, 2)
            expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = {} })
        end
        expect.equal(
            profile_switch.find_unowned_window_ids({
                UNOWNED_NOTES[1],
                {
                    window_id = 2,
                    bundle_id = "com.apple.Notes",
                    holder_numbers = { 2 },
                    is_minimized = false,
                },
            }),
            { 1 }
        )
    end,

    an_unknown_method_is_refused = function()
        expect.raises(function()
            profile_switch.plan_concealment("close_windows", UNOWNED_NOTES, 2)
        end, 'unknown concealment method "close_windows"')
        expect.equal(concealment_method.is_valid("close_windows"), false)
        expect.equal(concealment_method.is_valid(concealment_method.HIDE_APPLICATIONS), true)
    end,
}
