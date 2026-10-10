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
---@field log_info fun(message: string)

---A window to unminimize and fit, with the desktop it belongs on.
---@class WindowToBring
---@field window table an hs.window
---@field placement WindowPlacement
---@field space_id integer

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

local FRAME_TOLERANCE_POINTS = 2

---@param first Rect
---@param second Rect
---@return boolean
local function are_frames_close(first, second)
    return math.abs(first.x - second.x) <= FRAME_TOLERANCE_POINTS
        and math.abs(first.y - second.y) <= FRAME_TOLERANCE_POINTS
        and math.abs(first.w - second.w) <= FRAME_TOLERANCE_POINTS
        and math.abs(first.h - second.h) <= FRAME_TOLERANCE_POINTS
end

---Sets the saved frame of the window, unless the window already has it.
---@param window table an hs.window
---@param placement WindowPlacement
local function fit_frame(window, placement)
    local screen = read_screens.find_screen(placement.screen_uuid)
    if not screen or not placement.unit_frame then
        return
    end
    local target = screen:fromUnitRect(placement.unit_frame)
    if not are_frames_close(read_screens.to_rect(window:frame()), read_screens.to_rect(target)) then
        window:setFrame(target, 0)
    end
end

---@param placement WindowPlacement
---@return integer|nil the space of the desktop that the placement names
local function find_target_space_id(placement)
    local screen = read_screen_desktops(placement.screen_uuid)
    return screen and screen.space_ids[placement.desktop_number]
end

---@param placements WindowPlacement[]
---@param find_space_id fun(placement: WindowPlacement): integer|nil
---@param context RestoreContext
---@param failures string[]
---@return WindowToBring[]
local function resolve_windows(placements, find_space_id, context, failures)
    local windows_to_bring = {}
    for _, placement in ipairs(placements) do
        local window = context.find_window(placement.window_id)
        local space_id = find_space_id(placement)
        if not window then
            table.insert(failures, string.format("window %d was not found", placement.window_id))
        elseif not space_id then
            table.insert(
                failures,
                string.format(
                    "desktop %d of screen %s was not found",
                    placement.desktop_number,
                    placement.screen_uuid
                )
            )
        else
            table.insert(
                windows_to_bring,
                { window = window, placement = placement, space_id = space_id }
            )
        end
    end
    return windows_to_bring
end

---@param windows_to_bring WindowToBring[]
---@return boolean
local function are_all_unminimized(windows_to_bring)
    for _, entry in ipairs(windows_to_bring) do
        if entry.window:isMinimized() then
            return false
        end
    end
    return true
end

---Unminimizes the windows together, fits their frames, and passes on the windows that are not on
---their desktop afterwards.
---@param windows_to_bring WindowToBring[]
---@param timing Timing
---@param on_done fun(off_desktop: WindowToBring[])
local function unminimize_and_fit(windows_to_bring, timing, on_done)
    if #windows_to_bring == 0 then
        on_done({})
        return
    end
    for _, entry in ipairs(windows_to_bring) do
        if entry.window:isMinimized() then
            entry.window:unminimize()
        end
    end
    poll_until.wait(
        function()
            return are_all_unminimized(windows_to_bring)
        end,
        timing.minimize_timeout_seconds,
        timing.poll_interval_seconds,
        function()
            retained_timers.after(timing.window_settle_seconds, function()
                for _, entry in ipairs(windows_to_bring) do
                    fit_frame(entry.window, entry.placement)
                end
                retained_timers.after(timing.window_settle_seconds, function()
                    local off_desktop = {}
                    for _, entry in ipairs(windows_to_bring) do
                        local space_id =
                            read_desktops.find_window_space_id(entry.placement.window_id)
                        if space_id ~= entry.space_id then
                            table.insert(off_desktop, entry)
                        end
                    end
                    on_done(off_desktop)
                end)
            end)
        end
    )
end

---Moves the windows to the desktop that shows on their recorded screen, and fits their frames.
---Setting the frame of a window onto another screen moves it to the desktop that shows there.
---@param placements WindowPlacement[]
---@param space_id integer
---@param context RestoreContext
---@param failures string[]
---@param on_done fun()
local function bring_windows(placements, space_id, context, failures, on_done)
    local windows_to_bring = resolve_windows(placements, function()
        return space_id
    end, context, failures)
    unminimize_and_fit(windows_to_bring, context.timing, function(off_desktop)
        for _, entry in ipairs(off_desktop) do
            table.insert(
                failures,
                string.format(
                    "%s stayed off desktop %d of its screen",
                    track_windows.describe(entry.window),
                    entry.placement.desktop_number
                )
            )
        end
        on_done()
    end)
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

---Shows each desktop in turn and brings its windows there.
---@param visits DesktopVisit[]
---@param context RestoreContext
---@param failures string[]
---@param on_done fun()
local function run_visits(visits, context, failures, on_done)
    local next_index = 1
    local function visit_next()
        local visit = visits[next_index]
        if visit == nil then
            on_done()
            return
        end
        next_index = next_index + 1
        show_desktop(
            visit.screen_uuid,
            visit.desktop_number,
            context,
            function(space_id, error_message)
                if error_message or not space_id then
                    table.insert(failures, error_message or "the desktop was not found")
                    visit_next()
                    return
                end
                bring_windows(visit.placements, space_id, context, failures, visit_next)
            end
        )
    end
    visit_next()
end

---@param addition DesktopAddition
---@param context RestoreContext
---@param failures string[]
---@param on_done fun()
local function add_desktops(addition, context, failures, on_done)
    local screen = read_screens.find_screen(addition.screen_uuid)
    if not screen then
        table.insert(failures, string.format("screen %s is gone", addition.screen_uuid))
        on_done()
        return
    end
    mission_control_desktops.add_desktops(
        screen:id(),
        addition.desktops_to_add,
        context.timing,
        function(error_message)
            if error_message then
                table.insert(failures, "Adding desktops failed: " .. error_message)
            end
            on_done()
        end
    )
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
    for _, addition in ipairs(plan.desktop_additions) do
        table.insert(steps, function(continue)
            add_desktops(addition, context, failures, continue)
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
    table.insert(steps, function(continue)
        local windows_to_bring =
            resolve_windows(plan.unminimizations_in_place, find_target_space_id, context, failures)
        unminimize_and_fit(windows_to_bring, context.timing, function(off_desktop)
            for _, entry in ipairs(off_desktop) do
                context.log_info(
                    string.format(
                        "%s stays off desktop %d of its screen, where macOS cannot move it",
                        track_windows.describe(entry.window),
                        entry.placement.desktop_number
                    )
                )
            end
            continue()
        end)
    end)
    table.insert(steps, function(continue)
        run_visits(plan.visits, context, failures, continue)
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
