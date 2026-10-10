local mission_control_desktops = require("desktop_manager.macos.mission_control_desktops")
local poll_until = require("desktop_manager.macos.poll_until")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local retained_timers = require("desktop_manager.macos.retained_timers")
local step_sequence = require("desktop_manager.core.step_sequence")
local switch_desktops = require("desktop_manager.macos.switch_desktops")
local track_windows = require("desktop_manager.macos.track_windows")

local restore_windows = {}

---@class RestoreContext
---@field timing Timing
---@field find_window fun(window_id: integer): table|nil returns the hs.window of an id

---@param screen_uuid string
---@return ScreenDesktops|nil
local function read_screen_desktops(screen_uuid)
    for _, screen in ipairs(read_desktops.read_desktop_layout().screens) do
        if screen.screen_uuid == screen_uuid then
            return screen
        end
    end
    return nil
end

---@param window table an hs.window
---@param placement WindowPlacement
local function fit_frame(window, placement)
    local screen = read_screens.find_screen(placement.screen_uuid)
    if screen and placement.unit_frame then
        window:setFrame(screen:fromUnitRect(placement.unit_frame), 0)
    end
end

---@param window_id integer
---@return boolean
local function is_on_visible_desktop(window_id)
    local space_id = read_desktops.find_window_space_id(window_id)
    return space_id ~= nil and read_desktops.is_space_active(space_id)
end

---Brings one window to the desktop that is showing, and fits its frame.
---A window on a hidden desktop is minimized and unminimized, which moves it to the shown desktop
---if macOS unminimizes onto the current desktop. The check afterwards reports a window that stayed.
---@param placement WindowPlacement
---@param space_id integer
---@param context RestoreContext
---@param failures string[]
---@param on_done fun()
local function bring_window(placement, space_id, context, failures, on_done)
    local timing = context.timing
    local window = context.find_window(placement.window_id)
    if not window then
        table.insert(failures, string.format("window %d was not found", placement.window_id))
        on_done()
        return
    end
    local function fit_and_check()
        fit_frame(window, placement)
        retained_timers.after(timing.window_settle_seconds, function()
            if read_desktops.find_window_space_id(placement.window_id) ~= space_id then
                table.insert(
                    failures,
                    string.format(
                        "%s stayed off desktop %d of its screen",
                        track_windows.describe(window),
                        placement.desktop_number
                    )
                )
            end
            on_done()
        end)
    end
    local function unminimize_here()
        window:unminimize()
        retained_timers.after(timing.window_settle_seconds, fit_and_check)
    end
    if window:isMinimized() then
        unminimize_here()
    elseif is_on_visible_desktop(placement.window_id) then
        fit_and_check()
    else
        window:minimize()
        poll_until.wait(function()
            return window:isMinimized()
        end, timing.minimize_timeout_seconds, timing.poll_interval_seconds, unminimize_here)
    end
end

---@param placements WindowPlacement[]
---@param space_id integer
---@param context RestoreContext
---@param failures string[]
---@param on_done fun()
local function bring_windows(placements, space_id, context, failures, on_done)
    local next_index = 1
    local function bring_next()
        local placement = placements[next_index]
        if placement == nil then
            on_done()
            return
        end
        next_index = next_index + 1
        bring_window(placement, space_id, context, failures, bring_next)
    end
    bring_next()
end

---@param screen_uuid string
---@param desktop_number integer
---@param context RestoreContext
---@param on_done fun(space_id: integer|nil, error_message: string|nil)
local function show_desktop(screen_uuid, desktop_number, context, on_done)
    local screen = read_screen_desktops(screen_uuid)
    local space_ids = screen and screen.space_ids or {}
    local space_id = space_ids[math.min(desktop_number, #space_ids)]
    if not space_id then
        on_done(nil, string.format("screen %s has no desktops", screen_uuid))
        return
    end
    switch_desktops.switch_to_space(space_id, context.timing, function(error_message)
        on_done(space_id, error_message)
    end)
end

---@param change DesktopCountChange
---@param context RestoreContext
---@param failures string[]
---@param on_done fun()
local function change_desktop_count(change, context, failures, on_done)
    local screen = read_screens.find_screen(change.screen_uuid)
    if not screen then
        table.insert(failures, string.format("screen %s is gone", change.screen_uuid))
        on_done()
        return
    end
    local function report(error_message)
        if error_message then
            table.insert(failures, "Changing the number of desktops failed: " .. error_message)
        end
        on_done()
    end
    if change.desktops_to_add > 0 then
        mission_control_desktops.add_desktops(
            screen:id(),
            change.desktops_to_add,
            context.timing,
            report
        )
        return
    end
    local function remove()
        mission_control_desktops.remove_desktops(
            screen:id(),
            change.screen_uuid,
            change.space_ids_to_remove,
            context.timing,
            report
        )
    end
    local desktops = read_screen_desktops(change.screen_uuid)
    for _, space_id in ipairs(change.space_ids_to_remove) do
        if desktops and desktops.active_space_id == space_id then
            show_desktop(change.screen_uuid, 1, context, function(_, error_message)
                if error_message then
                    report(error_message)
                    return
                end
                remove()
            end)
            return
        end
    end
    remove()
end

---@param plan RestorePlan
---@param context RestoreContext
---@param failures string[]
---@return Step[]
local function build_steps(plan, context, failures)
    local steps = {}
    table.insert(steps, function(continue)
        for _, bundle_id in ipairs(plan.bundle_ids_to_unhide) do
            for _, application in ipairs(hs.application.applicationsForBundleID(bundle_id)) do
                application:unhide()
            end
        end
        retained_timers.after(context.timing.window_settle_seconds, continue)
    end)
    for _, change in ipairs(plan.desktop_count_changes) do
        table.insert(steps, function(continue)
            change_desktop_count(change, context, failures, continue)
        end)
    end
    table.insert(steps, function(continue)
        for _, placement in ipairs(plan.placements_in_place) do
            local window = context.find_window(placement.window_id)
            if window then
                fit_frame(window, placement)
            end
        end
        continue()
    end)
    for _, visit in ipairs(plan.visits) do
        table.insert(steps, function(continue)
            show_desktop(
                visit.screen_uuid,
                visit.desktop_number,
                context,
                function(space_id, error_message)
                    if error_message or not space_id then
                        table.insert(failures, error_message or "the desktop was not found")
                        continue()
                        return
                    end
                    bring_windows(visit.placements, space_id, context, failures, continue)
                end
            )
        end)
    end
    table.insert(steps, function(continue)
        for _, window_id in ipairs(plan.window_ids_to_minimize) do
            local window = context.find_window(window_id)
            if window then
                window:minimize()
            end
        end
        continue()
    end)
    if plan.focus then
        table.insert(steps, function(continue)
            show_desktop(
                plan.focus.screen_uuid,
                plan.focus.desktop_number,
                context,
                function(_, error_message)
                    if error_message then
                        table.insert(failures, error_message)
                    end
                    continue()
                end
            )
        end)
    end
    return steps
end

---Carries out a restore plan, and calls `on_done` with the failures that the user should hear of.
---@param plan RestorePlan
---@param context RestoreContext
---@param on_done fun(failures: string[])
function restore_windows.apply(plan, context, on_done)
    local failures = {}
    step_sequence.run(
        build_steps(plan, context, failures),
        retained_timers.defer,
        function(error_message)
            if error_message then
                table.insert(failures, error_message)
            end
            on_done(failures)
        end
    )
end

return restore_windows
