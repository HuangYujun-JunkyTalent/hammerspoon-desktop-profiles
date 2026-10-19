local mission_control_desktops = require("desktop_manager.macos.mission_control_desktops")
local move_windows = require("desktop_manager.macos.move_windows")
local poll_until = require("desktop_manager.macos.poll_until")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local retained_timers = require("desktop_manager.macos.retained_timers")
local step_sequence = require("desktop_manager.core.step_sequence")
local window_routes = require("desktop_manager.core.window_routes")

---Brings the windows of a restore plan to their desktops and frames without a switch of desktops,
---as `window_routes` plans the way of each window.
local restore_windows = {}

---@class RestoreContext
---@field timing Timing
---@field find_window fun(window_id: integer): table|nil returns the hs.window of an id
---@field show_busy_message fun(text: string)
---@field busy_text string the message of the whole restore, which shows again after a step with a
---message of its own
---@field describe_window fun(window_id: integer): string such as 'Safari window "Inbox"'
---@field is_current fun(): boolean whether the switch or the restore still runs, false once the
---watchdog has stopped it, so that no later step acts

---The route of a window, with the placement it serves and the hs.window.
---@class PlannedRoute
---@field route WindowRoute
---@field placement WindowPlacement
---@field window table

---@param additions DesktopAddition[]
---@return string
local function describe_additions(additions)
    local count = 0
    for _, addition in ipairs(additions) do
        count = count + addition.desktops_to_add
    end
    if #additions == 1 then
        return string.format(
            "Adding %d desktops to %s… please wait",
            count,
            additions[1].slot_key
        )
    end
    return string.format("Adding %d desktops… please wait", count)
end

---Adds the desktops of every screen in one opening of Mission Control.
---@param additions DesktopAddition[]
---@param context RestoreContext
---@param failures string[]
---@param on_done fun()
local function add_desktops(additions, context, failures, on_done)
    if #additions == 0 then
        on_done()
        return
    end
    context.show_busy_message(describe_additions(additions))
    local edits = {}
    for _, addition in ipairs(additions) do
        table.insert(edits, {
            screen_uuid = addition.screen_uuid,
            slot_key = addition.slot_key,
            desktops_to_add = addition.desktops_to_add,
            space_ids_to_remove = {},
        })
    end
    mission_control_desktops.edit(
        edits,
        function()
            return nil
        end,
        context.timing,
        function(edit_failures)
            for _, failure in ipairs(edit_failures) do
                table.insert(failures, failure)
            end
            context.show_busy_message(context.busy_text)
            on_done()
        end
    )
end

---Unminimizes the windows together, and waits until macOS has unminimized them.
---macOS 27.0.1 unminimizes a window onto the desktop it was minimized on.
---@param placements WindowPlacement[]
---@param context RestoreContext
---@param on_done fun()
local function unminimize_windows(placements, context, on_done)
    local windows = {}
    for _, placement in ipairs(placements) do
        local window = context.find_window(placement.window_id)
        if window and window:isMinimized() then
            window:unminimize()
            table.insert(windows, window)
        end
    end
    if #windows == 0 then
        on_done()
        return
    end
    poll_until.wait(
        function()
            for _, window in ipairs(windows) do
                if window:isMinimized() then
                    return false
                end
            end
            return true
        end,
        context.timing.minimize_timeout_seconds,
        context.timing.poll_interval_seconds,
        function()
            retained_timers.after(context.timing.window_settle_seconds, on_done)
        end
    )
end

---Plans the route of each placement from where macOS lists its window now.
---@param placements WindowPlacement[]
---@param context RestoreContext
---@param failures string[]
---@return PlannedRoute[]
local function plan_routes(placements, context, failures)
    local desktop_layout = read_desktops.read_desktop_layout()
    local planned = {}
    for _, placement in ipairs(placements) do
        local window = context.find_window(placement.window_id)
        if not window then
            table.insert(failures, string.format("window %d was not found", placement.window_id))
        else
            local location = {
                space_ids = read_desktops.list_window_space_ids(placement.window_id),
                frame = read_screens.to_rect(window:frame()),
            }
            local route, reason = window_routes.plan(placement, location, desktop_layout)
            if reason then
                table.insert(
                    failures,
                    context.describe_window(placement.window_id) .. " " .. reason
                )
            elseif route then
                table.insert(planned, { route = route, placement = placement, window = window })
            end
        end
    end
    return planned
end

---Moves the windows of the routes by their ids, and calls `on_done` with the routes whose window
---arrived.
---@param planned PlannedRoute[]
---@param find_space_id fun(route: WindowRoute): integer|nil the desktop of the move, nil for none
---@param describe_failure fun(entry: PlannedRoute, message: string): string
---@param context RestoreContext
---@param failures string[]
---@param on_done fun(arrived: PlannedRoute[])
local function move_routes(planned, find_space_id, describe_failure, context, failures, on_done)
    local moves = {}
    for _, entry in ipairs(planned) do
        local space_id = find_space_id(entry.route)
        if space_id then
            table.insert(moves, { window_id = entry.route.window_id, space_id = space_id })
        end
    end
    move_windows.move_all(moves, context.timing, function(move_failures)
        local has_failed = {}
        for _, failure in ipairs(move_failures) do
            has_failed[failure.window_id] = true
            for _, entry in ipairs(planned) do
                if entry.route.window_id == failure.window_id then
                    table.insert(failures, describe_failure(entry, failure.message))
                end
            end
        end
        local arrived = {}
        for _, entry in ipairs(planned) do
            if not has_failed[entry.route.window_id] then
                table.insert(arrived, entry)
            end
        end
        on_done(arrived)
    end)
end

---Sets the frames of the routes that have one, each while its window is on the desktop in view.
---Setting the frame of a window onto another screen moves it to the desktop that shows there.
---@param planned PlannedRoute[]
---@param context RestoreContext
---@param on_done fun()
local function set_frames(planned, context, on_done)
    local has_set_frame = false
    for _, entry in ipairs(planned) do
        if entry.route.target_frame then
            entry.window:setFrame(entry.route.target_frame, 0)
            has_set_frame = true
        end
    end
    if not has_set_frame then
        on_done()
        return
    end
    retained_timers.after(context.timing.window_settle_seconds, on_done)
end

---Keeps the routes whose window is on the screen of its placement, which a move by id needs.
---A route across screens whose window stayed off that screen ends with a failure.
---@param planned PlannedRoute[]
---@param context RestoreContext
---@param failures string[]
---@return PlannedRoute[]
local function keep_routes_on_their_screens(planned, context, failures)
    local kept = {}
    for _, entry in ipairs(planned) do
        local space_id = read_desktops.find_window_space_id(entry.route.window_id)
        local screen = space_id and read_desktops.find_screen_of_space(space_id)
        if screen and screen.screen_uuid == entry.route.target_screen_uuid then
            table.insert(kept, entry)
        else
            table.insert(
                failures,
                string.format(
                    "%s stayed off screen %s",
                    context.describe_window(entry.route.window_id),
                    entry.placement.slot_key
                )
            )
        end
    end
    return kept
end

---@param plan RestorePlan
---@param context RestoreContext
---@param failures string[]
---@return Step[]
local function build_steps(plan, context, failures)
    local planned = {}
    local steps = {}
    table.insert(steps, function(continue)
        for _, bundle_id in ipairs(plan.bundle_ids_to_unhide) do
            for _, application in ipairs(hs.application.applicationsForBundleID(bundle_id)) do
                application:unhide()
            end
        end
        retained_timers.after(context.timing.window_settle_seconds, function()
            for _, bundle_id in ipairs(plan.bundle_ids_to_unhide) do
                for _, application in ipairs(hs.application.applicationsForBundleID(bundle_id)) do
                    if application:isHidden() then
                        table.insert(failures, application:name() .. " stayed hidden")
                    end
                end
            end
            continue()
        end)
    end)
    table.insert(steps, function(continue)
        add_desktops(plan.desktop_additions, context, failures, continue)
    end)
    table.insert(steps, function(continue)
        unminimize_windows(plan.unminimizations, context, continue)
    end)
    table.insert(steps, function(continue)
        planned = plan_routes(plan.placements, context, failures)
        move_routes(
            planned,
            function(route)
                return route.view_space_id
            end,
            function(entry, message)
                return string.format(
                    "%s did not come into view to take its frame: %s",
                    context.describe_window(entry.route.window_id),
                    message
                )
            end,
            context,
            failures,
            function(arrived)
                planned = arrived
                continue()
            end
        )
    end)
    table.insert(steps, function(continue)
        set_frames(planned, context, continue)
    end)
    table.insert(steps, function(continue)
        planned = keep_routes_on_their_screens(planned, context, failures)
        move_routes(
            planned,
            function(route)
                return route.target_space_id
            end,
            function(entry, message)
                return string.format(
                    "%s did not reach desktop %d of %s: %s",
                    context.describe_window(entry.route.window_id),
                    entry.placement.desktop_number,
                    entry.placement.slot_key,
                    message
                )
            end,
            context,
            failures,
            function()
                continue()
            end
        )
    end)
    return steps
end

---Carries out a restore plan, and calls `on_done` with the failures that the user should hear of.
---A restore that the watchdog stopped ends before its next step, and calls `on_done` no more.
---The steps are: unhide the applications, add the desktops in one opening of Mission Control,
---unminimize the windows together, bring into view by id the windows that need a frame, set the
---frames, and move the windows on their screens to their desktops by id.
---The desktops of `plan.shown_desktops` are left to the caller, which shows the desktop of the
---screen of the focus in the last opening of Mission Control, after the removal of the extra
---desktops.
---@param plan RestorePlan
---@param context RestoreContext
---@param on_done fun(failures: string[])
function restore_windows.apply(plan, context, on_done)
    local failures = {}
    local steps = {}
    for _, step in ipairs(build_steps(plan, context, failures)) do
        table.insert(steps, function(continue)
            if context.is_current() then
                step(continue)
            end
        end)
    end
    step_sequence.run(steps, retained_timers.defer, function(error_message)
        if error_message then
            table.insert(failures, error_message)
        end
        on_done(failures)
    end)
end

return restore_windows
