local move_windows = require("desktop_manager.macos.move_windows")
local reach_plan = require("desktop_manager.core.reach_plan")
local read_desktops = require("desktop_manager.macos.read_desktops")
local track_windows = require("desktop_manager.macos.track_windows")

---Moves the windows that accessibility does not reach into view by their ids, so that a switch or
---a restore can act on them, and moves those that accessibility does not reach in view either back.
local reach_windows = {}

---@class ReachContext
---@field timing Timing
---@field log table an hs.logger
---@field show_busy_message fun(text: string)
---@field continue fun(callback: function): function wraps a callback of a step, so that the
---callback does nothing once the watchdog has stopped the switch or the restore
---@field remember_reached_window fun(window_id: integer, window: table) keeps the hs.window of a
---window that accessibility reached in view

---Moves a window that came into view and that accessibility did not reach there back to its
---desktop by its id, because the switch can neither minimize it nor set its frame, and reports it.
---@param windows ServerWindow[] the windows that accessibility did not reach
---@param desktop_numbers table<integer, integer> the desktop of each window before its move
---@param context ReachContext
---@param on_done fun(failures: string[])
local function move_unreached_windows_back(windows, desktop_numbers, context, on_done)
    if #windows == 0 then
        on_done({})
        return
    end
    local moves = {}
    for _, window in ipairs(windows) do
        table.insert(moves, { window_id = window.window_id, space_id = window.space_id })
    end
    move_windows.move_all(
        moves,
        context.timing,
        context.continue(function(move_failures)
            local back_failures, failures = {}, {}
            for _, failure in ipairs(move_failures) do
                back_failures[failure.window_id] = failure.message
            end
            for _, window in ipairs(windows) do
                local back_failure = back_failures[window.window_id]
                if back_failure then
                    table.insert(
                        failures,
                        string.format(
                            "%s window %q stays in view, because accessibility did not reach it"
                                .. " there and it did not go back: %s",
                            window.app_name,
                            window.title,
                            back_failure
                        )
                    )
                else
                    table.insert(
                        failures,
                        string.format(
                            "%s window %q stays on desktop %d,"
                                .. " because accessibility did not reach it in view",
                            window.app_name,
                            window.title,
                            desktop_numbers[window.window_id]
                        )
                    )
                end
            end
            on_done(failures)
        end)
    )
end

---Moves the windows that accessibility does not reach by their ids to the desktop in view of their
---screens, where Hammerspoon sees them, so that a switch or a restore can act on them, and waits
---until accessibility reaches them.
---A reached window shows on the desktop in view until the switch or the restore moves it back or
---takes it out of sight.
---A window that accessibility does not reach in view either goes back to its desktop.
---@param windows ServerWindow[]
---@param context ReachContext
---@param on_done fun(failures: string[])
function reach_windows.reach(windows, context, on_done)
    if #windows == 0 then
        on_done({})
        return
    end
    context.log.f("moving %d windows into view to reach them", #windows)
    context.show_busy_message("Finding the windows on other desktops… please wait")
    local timing = context.timing
    local plan = reach_plan.plan_moves_into_view(windows, read_desktops.read_desktop_layout())
    local moves, desktop_numbers = plan.moves, plan.desktop_numbers
    local failures, window_by_id = {}, {}
    for _, window in ipairs(windows) do
        window_by_id[window.window_id] = window
    end
    for _, window in ipairs(plan.windows_without_shown_desktop) do
        table.insert(
            failures,
            string.format(
                "%s window %q stays out of reach, because its screen shows no desktop",
                window.app_name,
                window.title
            )
        )
    end
    move_windows.move_all(
        moves,
        timing,
        context.continue(function(move_failures)
            local has_failed = {}
            for _, failure in ipairs(move_failures) do
                local window = window_by_id[failure.window_id]
                has_failed[failure.window_id] = true
                table.insert(
                    failures,
                    string.format(
                        "%s window %q stays out of reach: %s",
                        window.app_name,
                        window.title,
                        failure.message
                    )
                )
            end
            local moved = {}
            for _, move in ipairs(moves) do
                if not has_failed[move.window_id] then
                    table.insert(moved, window_by_id[move.window_id])
                end
            end
            track_windows.wait_until_reached(
                moved,
                timing.window_reach_timeout_seconds,
                context.continue(function(reached)
                    local unreached = {}
                    for _, window in ipairs(moved) do
                        if reached[window.window_id] then
                            context.remember_reached_window(
                                window.window_id,
                                reached[window.window_id]
                            )
                        else
                            table.insert(unreached, window)
                        end
                    end
                    move_unreached_windows_back(
                        unreached,
                        desktop_numbers,
                        context,
                        function(back_failures)
                            for _, failure in ipairs(back_failures) do
                                table.insert(failures, failure)
                            end
                            on_done(failures)
                        end
                    )
                end)
            )
        end)
    )
end

return reach_windows
