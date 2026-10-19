local concealment_method = require("desktop_manager.core.concealment_method")
local expect = require("tests.expect")
local profile_switch = require("desktop_manager.core.profile_switch")

local BOTH_METHODS = { concealment_method.MINIMIZE_WINDOWS, concealment_method.HIDE_APPLICATIONS }

---@param window_id integer
---@param bundle_id string
---@return OpenWindow
local function open_window(window_id, bundle_id)
    return {
        window_id = window_id,
        bundle_id = bundle_id,
        is_minimized = false,
        is_app_hidden = false,
    }
end

---@param window_id integer
---@param is_out_of_sight boolean
---@return WindowMatch
local function match_of(window_id, is_out_of_sight)
    return {
        window_id = window_id,
        record = {
            window_id = window_id,
            bundle_id = "com.apple.Safari",
            app_name = "Safari",
            title = tostring(window_id),
            is_out_of_sight = is_out_of_sight,
        },
    }
end

---@param window_id integer
---@param bundle_id string
---@param is_in_sight boolean
---@param is_kept boolean
---@return SwitchCandidate
local function candidate(window_id, bundle_id, is_in_sight, is_kept)
    return {
        window_id = window_id,
        bundle_id = bundle_id,
        is_in_sight = is_in_sight,
        is_kept = is_kept,
    }
end

return {
    the_profile_entered_keeps_the_windows_it_recorded_in_sight = function()
        local candidates = profile_switch.mark_kept_windows(
            { open_window(41, "com.apple.Safari"), open_window(42, "com.apple.Safari") },
            { match_of(41, false), match_of(42, true) }
        )
        expect.equal(candidates[1].is_kept, true)
        expect.equal(candidates[2].is_kept, false)
    end,

    a_window_recorded_by_another_profile_alone_goes_out_of_sight = function()
        local open_windows = { open_window(43, "com.microsoft.Word") }
        expect.equal(profile_switch.mark_kept_windows(open_windows, {})[1].is_kept, false)
        expect.equal(
            profile_switch.mark_kept_windows_for_new_profile(
                open_windows,
                { [43] = { ["com.microsoft.Word"] = true } }
            )[1].is_kept,
            false
        )
    end,

    a_profile_without_a_layout_keeps_a_window_that_no_profile_recorded = function()
        local recorded_for_another_application = { [44] = { ["com.apple.Safari"] = true } }
        local candidates = profile_switch.mark_kept_windows_for_new_profile(
            { open_window(44, "com.apple.Notes") },
            recorded_for_another_application
        )
        expect.equal(candidates[1].is_kept, true)
        expect.equal(candidates[1].is_in_sight, true)
    end,

    a_profile_with_a_layout_conceals_a_window_that_no_profile_recorded = function()
        local candidates = profile_switch.mark_kept_windows(
            { open_window(44, "com.apple.Notes") },
            {}
        )
        expect.equal(candidates[1].is_kept, false)
        expect.equal(candidates[1].is_in_sight, true)
    end,

    minimizing_takes_the_windows_in_sight_that_are_not_kept = function()
        local plan = profile_switch.plan_concealment(concealment_method.MINIMIZE_WINDOWS, {
            candidate(1, "com.microsoft.Word", true, false),
            candidate(2, "com.microsoft.Word", false, false),
            candidate(3, "com.apple.Safari", true, true),
        })
        expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = { 1 } })
    end,

    hiding_takes_an_application_without_kept_windows = function()
        local plan = profile_switch.plan_concealment(concealment_method.HIDE_APPLICATIONS, {
            candidate(1, "com.microsoft.Word", true, false),
            candidate(2, "com.microsoft.Word", false, false),
        })
        expect.equal(
            plan,
            { bundle_ids_to_hide = { "com.microsoft.Word" }, window_ids_to_minimize = {} }
        )
    end,

    hiding_minimizes_the_other_windows_of_an_application_with_a_kept_window = function()
        local plan = profile_switch.plan_concealment(concealment_method.HIDE_APPLICATIONS, {
            candidate(1, "com.apple.Safari", true, false),
            candidate(2, "com.apple.Safari", true, true),
        })
        expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = { 1 } })
    end,

    windows_out_of_sight_need_nothing = function()
        for _, method in ipairs(BOTH_METHODS) do
            local plan = profile_switch.plan_concealment(method, {
                candidate(1, "com.apple.Notes", false, false),
                candidate(2, "com.apple.Notes", true, true),
            })
            expect.equal(plan, { bundle_ids_to_hide = {}, window_ids_to_minimize = {} })
        end
    end,

    an_unknown_method_is_refused = function()
        expect.raises(function()
            profile_switch.plan_concealment("close_windows", {})
        end, 'unknown concealment method "close_windows"')
        expect.equal(concealment_method.is_valid("close_windows"), false)
        expect.equal(concealment_method.is_valid(concealment_method.HIDE_APPLICATIONS), true)
    end,
}
