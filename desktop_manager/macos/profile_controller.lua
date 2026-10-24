local app_number_list = require("desktop_manager.macos.app_number_list")
local app_numbers = require("desktop_manager.core.app_numbers")
local app_pool = require("desktop_manager.core.app_pool")
local app_pool_window = require("desktop_manager.macos.app_pool_window")
local arrangement_capture = require("desktop_manager.core.arrangement_capture")
local busy_message = require("desktop_manager.macos.busy_message")
local color_window = require("desktop_manager.macos.color_window")
local concatenate_lists = require("desktop_manager.core.concatenate_lists")
local conceal_windows = require("desktop_manager.macos.conceal_windows")
local desktop_counts = require("desktop_manager.core.desktop_counts")
local diagnostic_lines = require("desktop_manager.macos.diagnostic_lines")
local extra_desktops = require("desktop_manager.macos.extra_desktops")
local hidden_application_filter = require("desktop_manager.macos.hidden_application_filter")
local highlight_colors = require("desktop_manager.core.highlight_colors")
local list_known_windows = require("desktop_manager.macos.list_known_windows")
local locate_desktops = require("desktop_manager.core.locate_desktops")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local mission_control_desktops = require("desktop_manager.macos.mission_control_desktops")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local open_missing_windows = require("desktop_manager.macos.open_missing_windows")
local profile_pause = require("desktop_manager.core.profile_pause")
local profile_state = require("desktop_manager.core.profile_state")
local profile_switch = require("desktop_manager.core.profile_switch")
local reach_plan = require("desktop_manager.core.reach_plan")
local reach_windows = require("desktop_manager.macos.reach_windows")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local restore_plan = require("desktop_manager.core.restore_plan")
local restore_windows = require("desktop_manager.macos.restore_windows")
local retained_timers = require("desktop_manager.macos.retained_timers")
local search_windows = require("desktop_manager.macos.search_windows")
local settings_check = require("desktop_manager.core.settings_check")
local shortcut_actions = require("desktop_manager.core.shortcut_actions")
local shortcut_center = require("keyboard_shortcuts.macos.shortcut_center")
local shortcut_window = require("keyboard_shortcuts.macos.shortcut_window")
local state_file = require("desktop_manager.macos.state_file")
local status_menu = require("desktop_manager.macos.status_menu")
local track_windows = require("desktop_manager.macos.track_windows")
local url_command = require("desktop_manager.core.url_command")
local window_inventory = require("desktop_manager.macos.window_inventory")
local window_matching = require("desktop_manager.core.window_matching")
local window_previews = require("desktop_manager.macos.window_previews")
local work_watchdog = require("desktop_manager.macos.work_watchdog")

local profile_controller = {}

local NANOSECONDS_PER_SECOND = 1e9
local MACOS_START_TIME_COMMAND = "/usr/sbin/sysctl -n kern.boottime"

local NOTIFICATION_TITLE = "Desktop Manager"
local FAILURE_ALERT_SECONDS = 8
local STILL_SWITCHING_MESSAGE = "Desktop Manager is still switching"
local MONITORS_CHANGED_MESSAGE = "Monitors changed, waiting for macOS… please wait"

---Owns the state, the hotkeys, the URL event, the menu bar item and the watchers.
---`is_switch_or_restore_running` is true while a switch or a restore moves windows, and then no
---arrangement is saved.
---`is_press_running` is true while a press of the list or the search shows a desktop through
---Mission Control, unhides an application or opens a window, and then no switch starts.
---@class ProfileController
---@field settings Settings
---@field state State
---@field log table an hs.logger
---@field window_filter table an hs.window.filter
---@field menubar table an hs.menubar
---@field shortcuts ShortcutCenter
---@field watchers table[]
---@field is_switch_or_restore_running boolean
---@field is_press_running boolean
---@field watchdog WorkWatchdog the numbers of the switches, the restores and the presses, and the
---timer that stops the one that does not end
---@field busy_message BusyMessage|nil the message on the screens while a switch, a restore or a
---press of the list or the search runs
---@field busy_message_text string|nil the text of the message
---@field app_pool_window AppPoolWindow|nil the window that chooses the managed applications
---@field color_window ColorWindow|nil the window that picks the colors of the search
---@field shortcut_window ShortcutWindow|nil the window that changes the shortcuts of every tool
---@field are_saves_suspended boolean
---@field save_timer table|nil
---@field screen_timer table|nil
---@field screen_signature string the screens that the last arrangement was restored for
---@field window_ids_out_of_sight table<integer, boolean> the windows that the last switch took out
---of sight
---@field app_number_list AppNumberList the list of numbered applications
---@field search_panel SearchPanel|nil the panel of the search of the windows while it shows
---@field window_inventory WindowInventory the windows that accessibility does not reach
---@field known_windows KnownWindows the windows that Hammerspoon knows
---@field preview_loader PreviewLoader the previews of the list and the search, which a slow
---snapshot stops until a reload
---@field hidden_states HiddenStates whether each application that the list or the search asked
---about is hidden
local ProfileController = {}
ProfileController.__index = ProfileController

---@param message string
local function notify(message)
    hs.notify.new({ title = NOTIFICATION_TITLE, informativeText = message }):send()
end

---@param value any
---@return string
local function inspect_on_one_line(value)
    return hs.inspect(value, { newline = " ", indent = "" })
end

---@param name string the name of the profile
---@return string the busy message of a switch to the profile
local function describe_arranging(name)
    return string.format("Arranging %s… please wait", name)
end

function ProfileController:write_state()
    if not state_file.write(self.settings.state_file_path, self.state) then
        self.log.e("the state could not be written to " .. self.settings.state_file_path)
    end
end

function ProfileController:refresh_menu()
    local function read_state()
        return self.state
    end
    status_menu.show(self.menubar, read_state, self.settings, {
        toggle_profile = function(number)
            self:toggle_profile(number)
        end,
        deactivate_profile = function()
            self:deactivate_profile()
        end,
        rename_active_profile = function()
            self:prompt_rename_active_profile()
        end,
        set_monitor_matching = function(matching)
            self:set_monitor_matching(matching)
        end,
        save_arrangement = function()
            self:capture_active_arrangement()
        end,
        print_diagnostics = function()
            self:print_diagnostics()
        end,
        clear_profile = function(number)
            self:clear_profile(number)
        end,
        open_app_pool_window = function()
            self:open_app_pool_window()
        end,
        open_shortcut_window = function()
            self:open_shortcut_window()
        end,
        open_color_window = function()
            self:open_color_window()
        end,
        choose_app_number = function(app_number, bundle_id, app_name)
            self:choose_app_number(app_number, bundle_id, app_name)
        end,
        release_app_number = function(app_number)
            self:release_app_number(app_number)
        end,
    })
end

---@return MonitorConfiguration
function ProfileController:read_monitor_configuration()
    local screens = read_screens.describe_screens(self.settings.builtin_screen_name_patterns)
    return monitor_configuration.describe(screens, self.state.monitor_matching)
end

---@param windows table[] hs.window objects
---@return OpenWindow[]
local function describe_open_windows(windows)
    local open_windows = {}
    for _, window in ipairs(windows) do
        local window_id = window:id()
        if window_id then
            local state = track_windows.read_window_state(window)
            table.insert(open_windows, {
                window_id = window_id,
                bundle_id = state.bundle_id,
                is_minimized = state.is_minimized,
                is_app_hidden = state.is_app_hidden,
                title = window:title() or "",
            })
        end
    end
    return open_windows
end

---Gives the records of a window that its application reopened the id of the new window, in every
---profile, under the policy that matches titles.
---A reopened window is an open window that no profile recorded, of the same application and with
---the same title as a recorded window that no longer exists.
---@param windows table[] the hs.window objects that the tool knows
function ProfileController:rename_reopened_windows(windows)
    if not missing_window_policy.matches_titles(self.settings.missing_window_policy) then
        return
    end
    local recorded = profile_state.index_recorded_windows(self.state)
    local unrecorded_windows = {}
    for _, window in ipairs(windows) do
        local window_id = window:id()
        local bundle_id = track_windows.bundle_id_of(window:application())
        if not (recorded[window_id] and recorded[window_id][bundle_id]) then
            table.insert(unrecorded_windows, {
                window_id = window_id,
                bundle_id = bundle_id,
                title = window:title() or "",
            })
        end
    end
    if #unrecorded_windows == 0 then
        return
    end
    local open_ids = track_windows.index_by_id(windows)
    local closed_records = window_matching.list_closed_records(
        profile_state.list_all_records(self.state),
        function(window_id)
            return open_ids[window_id] ~= nil
        end,
        function(window_id)
            return not read_desktops.find_window_space_id(window_id)
        end
    )
    local match_result =
        window_matching.match_records_to_reopened_windows(closed_records, unrecorded_windows)
    if #match_result.matches == 0 then
        return
    end
    local renames = {}
    for _, match in ipairs(match_result.matches) do
        table.insert(renames, profile_state.rename_of(match.record, match.window_id))
        self.log.f(
            "%s window %q was reopened as window %d, which was %d",
            match.record.app_name,
            match.record.title,
            match.window_id,
            match.record.window_id
        )
    end
    self.state = profile_state.rename_windows(self.state, renames)
    self:write_state()
end

---@param windows table[] hs.window objects
---@return WindowObservation[] observations of the windows that have an id
---@return table<integer, boolean> observed_ids
local function observe_windows(windows)
    local observations, observed_ids = {}, {}
    for _, window in ipairs(windows) do
        local observation = track_windows.observe(window)
        if observation.window_id then
            table.insert(observations, observation)
            observed_ids[observation.window_id] = true
        end
    end
    return observations, observed_ids
end

---Records every window of a managed application under the current monitor configuration.
---A window that Hammerspoon has not seen, on a desktop out of view, is recorded from the list of
---the window server, with its desktop and its frame.
---Such a window keeps the title of its previous record when the window server gives no title.
---A recorded window that neither Hammerspoon nor that list holds but that sits on a desktop keeps
---its previous record with its current desktop.
---While a switch or a restore runs, or while the monitors settle, nothing is recorded, because the
---windows and the desktops are on their way, and the end of that work schedules a save.
---Nothing is recorded while the active profile is paused either.
function ProfileController:capture_active_arrangement()
    local number = profile_state.find_profile_number_to_update(self.state)
    if not number or self.is_switch_or_restore_running or self.are_saves_suspended then
        return
    end
    local configuration = self:read_monitor_configuration()
    local managed_windows = self.known_windows:list_managed(
        profile_state.list_recorded_window_ids(
            profile_state.find_arrangement(self.state, number, configuration.key)
        )
    )
    self:rename_reopened_windows(managed_windows)
    local previous = profile_state.find_arrangement(self.state, number, configuration.key)
    local observations, observed_ids = observe_windows(managed_windows)
    local previous_records =
        app_pool.keep_managed(self.state.app_pool, previous and previous.windows or {})
    local previous_by_id = {}
    for _, record in ipairs(previous_records) do
        if record.window_id then
            previous_by_id[record.window_id] = record
        end
    end
    for _, window in ipairs(self.known_windows:list_unreached_managed(managed_windows)) do
        if not observed_ids[window.window_id] then
            observed_ids[window.window_id] = true
            table.insert(
                observations,
                arrangement_capture.observe_server_window(window, previous_by_id[window.window_id])
            )
        end
    end
    for _, record in ipairs(previous_records) do
        if record.window_id and not observed_ids[record.window_id] then
            local space_id = read_desktops.find_window_space_id(record.window_id)
            if space_id then
                table.insert(
                    observations,
                    arrangement_capture.observe_unlisted_record(record, space_id)
                )
            end
        end
    end
    local arrangement = arrangement_capture.capture(
        configuration,
        read_desktops.read_desktop_layout(),
        observations,
        previous
    )
    self.state = profile_state.with_arrangement(self.state, number, arrangement)
    self.state = profile_state.with_default_app_numbers(
        self.state,
        number,
        arrangement,
        configuration,
        self.settings.app_number_count
    )
    self:write_state()
end

---Gives profile 0 its default numbers from the windows open now, because it records no windows.
---A default number of profile 0 therefore stays while its application has a window open.
function ProfileController:update_numbers_of_profile_0()
    local configuration = self:read_monitor_configuration()
    local observations = observe_windows(self.known_windows:list_managed({}))
    local open_windows = arrangement_capture.capture(
        configuration,
        read_desktops.read_desktop_layout(),
        observations,
        nil
    )
    self.state = profile_state.with_default_app_numbers(
        self.state,
        profile_state.NO_PROFILE_NUMBER,
        open_windows,
        configuration,
        self.settings.app_number_count
    )
    self:write_state()
end

---Takes the desktops that the user added or removed into the number of desktops of each display.
---The state is written by the capture that follows.
function ProfileController:track_desktop_counts()
    local reading =
        desktop_counts.read(self:read_monitor_configuration(), read_desktops.read_desktop_layout())
    self.state = profile_state.with_desktop_counts(
        self.state,
        desktop_counts.update(self.state.desktop_counts, reading)
    )
end

---Updates the number of desktops of each display, and the record and the numbers of the active
---profile, or the numbers of profile 0 while no profile is active.
function ProfileController:update_records_and_numbers()
    self:track_desktop_counts()
    if self.state.active_profile_number then
        self:capture_active_arrangement()
    else
        self:update_numbers_of_profile_0()
    end
end

function ProfileController:schedule_save()
    if self.is_switch_or_restore_running or self.are_saves_suspended then
        return
    end
    retained_timers.stop(self.save_timer)
    self.save_timer = retained_timers.after(self.settings.timing.save_delay_seconds, function()
        self.save_timer = nil
        if not self.is_switch_or_restore_running and not self.are_saves_suspended then
            self:update_records_and_numbers()
        end
    end)
end

---Shows the text on every screen, and keeps the message that shows when it has the same text.
---@param text string
function ProfileController:show_busy_message(text)
    if self.busy_message and self.busy_message_text == text then
        return
    end
    self:close_busy_message()
    self.busy_message = busy_message.show(text)
    self.busy_message_text = text
end

function ProfileController:close_busy_message()
    if self.busy_message then
        busy_message.close(self.busy_message)
        self.busy_message = nil
        self.busy_message_text = nil
    end
end

---Closes the message at the end of a switch, a restore or a press, or shows the message of a change
---of monitors in its place while the restore after that change waits.
function ProfileController:end_busy_message()
    if self.screen_timer and profile_state.find_profile_number_to_update(self.state) then
        self:show_busy_message(MONITORS_CHANGED_MESSAGE)
        return
    end
    self:close_busy_message()
end

---Resumes the saves at the end of a restore, or once the watchdog has stopped a switch, a restore
---or a press, and schedules a save.
---While a later change of the monitors waits for its restore, the saves stay suspended until the
---end of that restore, because a save would record the windows on their way.
function ProfileController:resume_saves()
    if self.screen_timer then
        return
    end
    self.are_saves_suspended = false
    self:schedule_save()
end

---@param failures string[]
function ProfileController:report_failures(failures)
    for _, failure in ipairs(failures) do
        self.log.w(failure)
    end
    if #failures > 0 then
        local message =
            string.format("%s (%d problems in the Hammerspoon console)", failures[1], #failures)
        -- The alert shows where the busy message was, because a notification is easy to miss.
        hs.alert.show(message, FAILURE_ALERT_SECONDS)
        notify(message)
    end
end

---Brings the matched windows to the desktops and frames that the arrangement records.
---`on_done` also receives the recorded desktops to show, the desktop of the screen of the focus
---last, which the caller shows after the removal of the extra desktops.
---@param number integer
---@param arrangement Arrangement
---@param matches WindowMatch[]
---@param window_by_id table<integer, table> the hs.window of each matched window id
---@param busy_text string the message of the switch or the restore
---@param on_done fun(failures: string[], desktops_to_show: ScreenDesktop[])
function ProfileController:restore_matched_windows(
    number,
    arrangement,
    matches,
    window_by_id,
    busy_text,
    on_done
)
    local function find_window(window_id)
        return window_by_id[window_id] or self.known_windows:find(window_id)
    end
    local window_states = {}
    for _, match in ipairs(matches) do
        local window = find_window(match.window_id)
        if window then
            window_states[match.window_id] = track_windows.read_window_state(window)
        end
    end
    local plan = restore_plan.plan(
        arrangement,
        self:read_monitor_configuration(),
        read_desktops.read_desktop_layout(),
        matches,
        window_states
    )
    self.log.f(
        "restoring profile %d: %d of %d saved windows open, plan %s",
        number,
        #matches,
        #arrangement.windows,
        inspect_on_one_line(plan)
    )
    local context = {
        timing = self.settings.timing,
        find_window = find_window,
        show_busy_message = function(text)
            self:show_busy_message(text)
        end,
        busy_text = busy_text,
        describe_window = function(window_id)
            local window = find_window(window_id)
            return window and track_windows.describe(window)
                or string.format("window %d", window_id)
        end,
        is_current = self.watchdog:watch_current(),
    }
    restore_windows.apply(
        plan,
        context,
        self.watchdog:continue(function(failures)
            on_done(failures, plan.shown_desktops)
        end)
    )
end

---Matches the records of the arrangement against the known windows of the managed applications and
---the windows that accessibility does not reach, so that a record of an unreached window takes that
---window, and no new window opens for it.
---@param arrangement Arrangement
---@param managed_windows table[] hs.window objects
---@param unreached ServerWindow[]
---@return WindowMatchResult
---@return OpenWindow[] open_windows the known and the unreached windows, for the marks of a switch
function ProfileController:match_with_unreached(arrangement, managed_windows, unreached)
    local open_windows = describe_open_windows(managed_windows)
    for _, window in ipairs(unreached) do
        table.insert(open_windows, {
            window_id = window.window_id,
            bundle_id = window.bundle_id,
            is_minimized = false,
            is_app_hidden = false,
            title = window.title,
        })
    end
    local match_result = window_matching.match_records_to_open_windows(
        self.settings.match_windows_by,
        self.settings.missing_window_policy,
        arrangement.windows,
        open_windows
    )
    return match_result, open_windows
end

---Restores the open windows of an arrangement, and returns the recorded desktops to show.
---@param number integer
---@param saved_arrangement Arrangement
---@param busy_text string
---@param on_done fun(failures: string[], desktops: ScreenDesktop[])
function ProfileController:restore_open_windows(number, saved_arrangement, busy_text, on_done)
    local arrangement = app_pool.keep_managed_records(self.state.app_pool, saved_arrangement)
    local windows =
        self.known_windows:list_managed(profile_state.list_recorded_window_ids(arrangement))
    local match_result = self:match_with_unreached(
        arrangement,
        windows,
        self.known_windows:list_unreached_managed(windows)
    )
    self:restore_matched_windows(
        number,
        arrangement,
        match_result.matches,
        track_windows.index_by_id(windows),
        busy_text,
        on_done
    )
end

---Opens the new windows of the records in sight whose windows no longer exist, as
---`open_missing_windows.open_all` says, and writes the new window ids into the records of every
---profile before `on_done`.
---@param number integer
---@param unmatched_records WindowRecord[]
---@param on_done fun(failures: string[], new_matches: WindowMatch[])
function ProfileController:open_missing_windows(number, unmatched_records, on_done)
    open_missing_windows.open_all(
        number,
        unmatched_records,
        self:new_windows_context(),
        function(result)
            if #result.renames > 0 then
                self.state = profile_state.rename_windows(self.state, result.renames)
                self:write_state()
            end
            on_done(result.failures, result.new_matches)
        end
    )
end

---@return NewWindowsContext
function ProfileController:new_windows_context()
    return {
        timing = self.settings.timing,
        log = self.log,
        read_monitor_configuration = function()
            return self:read_monitor_configuration()
        end,
        continue = function(callback)
            return self.watchdog:continue(callback)
        end,
        action = self.settings.unmatched_window_action,
    }
end

---@return ReachContext
function ProfileController:reach_context()
    return {
        timing = self.settings.timing,
        log = self.log,
        show_busy_message = function(text)
            self:show_busy_message(text)
        end,
        continue = function(callback)
            return self.watchdog:continue(callback)
        end,
        remember_reached_window = function(window_id, window)
            self.known_windows:remember_reached(window_id, window)
        end,
    }
end

---Shows the recorded desktop, or desktop 1, of each screen that shows a space in full screen,
---because a window moved there by its id or by its frame would join the window in full screen.
---@param arrangement Arrangement|nil
---@param on_done fun(failures: string[])
function ProfileController:leave_full_screen(arrangement, on_done)
    extra_desktops.show_desktops(
        restore_plan.plan_exits_from_full_screen(
            arrangement,
            self:read_monitor_configuration(),
            read_desktops.read_desktop_layout()
        ),
        self:extra_desktops_context(),
        on_done
    )
end

---Brings the unreached windows that a switch or a restore acts on into view by their ids, after the
---screens that show a space in full screen show a desktop, as `leave_full_screen` says.
---@param arrangement Arrangement|nil
---@param windows_to_reach ServerWindow[]
---@param on_done fun(failures: string[])
function ProfileController:bring_into_view(arrangement, windows_to_reach, on_done)
    self:leave_full_screen(arrangement, function(exit_failures)
        reach_windows.reach(windows_to_reach, self:reach_context(), function(reach_failures)
            on_done(concatenate_lists.concatenate(exit_failures, reach_failures))
        end)
    end)
end

---Ends the work of a switch or a restore: stops its watchdog, lets the next work start, and closes
---its message.
---@param work_number integer
---@return boolean whether the work still ran, and the watchdog had not stopped it
function ProfileController:end_switch_or_restore_work(work_number)
    if not self.watchdog:stop(work_number) then
        return false
    end
    self.is_switch_or_restore_running = false
    self:end_busy_message()
    return true
end

---Ends a switch, a restore or a press that did not finish, so that the next one can start.
---The steps that still run act no further, because the number of the work has changed and the
---openings of Mission Control have stopped.
function ProfileController:stop_unfinished_work()
    local message = string.format(
        "Desktop Manager stopped a switch that did not finish within %g seconds",
        self.settings.timing.busy_watchdog_seconds
    )
    self.log.e(message)
    mission_control_desktops.stop_openings()
    self.is_switch_or_restore_running = false
    self.is_press_running = false
    self:end_busy_message()
    self:report_failures({ message })
    self:resume_saves()
end

---Switches to the profile, or restores the layout of the active profile while it is paused.
---@param number integer
function ProfileController:activate_profile(number)
    if self:refuse_while_busy() then
        return
    end
    if self.state.active_profile_number == number and not self.state.is_active_profile_paused then
        return
    end
    local started_at = hs.timer.secondsSinceEpoch()
    self:capture_active_arrangement()
    self.is_switch_or_restore_running = true
    local work_number = self.watchdog:start()
    retained_timers.stop(self.save_timer)
    local name = profile_state.profile_or_default(self.state, number).name
    self:show_busy_message(describe_arranging(name))
    self:switch_to_profile(number, name, started_at, work_number)
end

---The values that the steps of a switch to a profile share.
---@class RunningSwitch
---@field number integer the number of the profile
---@field name string the name of the profile
---@field busy_text string the message while the switch runs
---@field configuration MonitorConfiguration the monitor configuration when the switch started
---@field has_layout boolean whether the profile has a layout for the monitor configuration
---@field started_at number the time when the switch started, in seconds
---@field work_number integer the number of the switch, which the watchdog gave

---Conceals the windows that the profile does not keep, and restores the windows it records.
---The unreached windows that the switch acts on come into view by their ids first.
---@param number integer
---@param name string the name of the profile
---@param started_at number
---@param work_number integer
function ProfileController:switch_to_profile(number, name, started_at, work_number)
    local configuration = self:read_monitor_configuration()
    ---@type RunningSwitch
    local switch = {
        number = number,
        name = name,
        busy_text = describe_arranging(name),
        configuration = configuration,
        has_layout = profile_state.find_arrangement(self.state, number, configuration.key) ~= nil,
        started_at = started_at,
        work_number = work_number,
    }
    local windows = self:list_switch_windows(switch)
    local unreached = self.known_windows:list_unreached_managed(windows)
    local marked_windows = self:mark_switch_windows(switch, windows, unreached)
    local window_ids_to_reach = reach_plan.select_concealed(
        self.settings.concealment_method,
        unreached,
        marked_windows.candidates
    )
    if switch.has_layout then
        window_ids_to_reach = concatenate_lists.concatenate(
            reach_plan.select_misplaced(
                unreached,
                marked_windows.match_result.matches,
                configuration,
                read_desktops.read_desktop_layout()
            ),
            window_ids_to_reach
        )
    end
    local windows_to_reach = reach_plan.keep_windows_of_ids(unreached, window_ids_to_reach)
    if not switch.has_layout and #windows_to_reach == 0 then
        self:conceal_and_restore(switch, {})
        return
    end
    self:bring_into_view(marked_windows.arrangement, windows_to_reach, function(failures)
        self:conceal_and_restore(switch, failures)
    end)
end

---@param switch RunningSwitch
---@return Arrangement|nil the arrangement of the profile for the monitor configuration of the
---switch, read at each call, because the rename of reopened windows changes its records
function ProfileController:read_switch_arrangement(switch)
    return profile_state.find_arrangement(self.state, switch.number, switch.configuration.key)
end

---@param switch RunningSwitch
---@return table[] the hs.window objects of the managed applications, after the rename of the
---reopened windows
function ProfileController:list_switch_windows(switch)
    local windows = self.known_windows:list_managed(
        profile_state.list_recorded_window_ids(self:read_switch_arrangement(switch))
    )
    self:rename_reopened_windows(windows)
    return windows
end

---The records of a switch and the open windows that it keeps or takes out of sight.
---@class MarkedWindows
---@field arrangement Arrangement the arrangement of the switch, without the records of the
---applications that the desktop manager leaves to macOS
---@field match_result WindowMatchResult
---@field candidates SwitchCandidate[] the known and the unreached windows, marked by the switch

---@param switch RunningSwitch
---@param managed_windows table[]
---@param unreached ServerWindow[]
---@return MarkedWindows
function ProfileController:mark_switch_windows(switch, managed_windows, unreached)
    local arrangement = app_pool.keep_managed_records(
        self.state.app_pool,
        self:read_switch_arrangement(switch)
            or { monitor_configuration_key = switch.configuration.key, monitors = {}, windows = {} }
    )
    local match_result, open_windows =
        self:match_with_unreached(arrangement, managed_windows, unreached)
    local candidates = switch.has_layout
            and profile_switch.mark_kept_windows(open_windows, match_result.matches)
        or profile_switch.mark_kept_windows_for_new_profile(
            open_windows,
            profile_state.index_recorded_windows(self.state)
        )
    return { arrangement = arrangement, match_result = match_result, candidates = candidates }
end

---@param switch RunningSwitch
---@param failures string[]
function ProfileController:finish_switch(switch, failures)
    if not self:end_switch_or_restore_work(switch.work_number) then
        return
    end
    self:schedule_save()
    self.log.f(
        "profile %d is active after %.1f seconds, with %d problems",
        switch.number,
        hs.timer.secondsSinceEpoch() - switch.started_at,
        #failures
    )
    self:report_failures(failures)
end

---Takes the windows that the profile does not keep out of sight, makes the profile active, and
---restores its layout when it has one.
---@param switch RunningSwitch
---@param earlier_failures string[] the failures of the way into view
function ProfileController:conceal_and_restore(switch, earlier_failures)
    self:show_busy_message(switch.busy_text)
    local windows = self:list_switch_windows(switch)
    local marked_windows = self:mark_switch_windows(
        switch,
        windows,
        self.known_windows:list_unreached_managed(windows)
    )
    self.window_ids_out_of_sight = {}
    for _, candidate in ipairs(marked_windows.candidates) do
        if not candidate.is_kept then
            self.window_ids_out_of_sight[candidate.window_id] = true
        end
    end
    local concealment =
        profile_switch.plan_concealment(self.settings.concealment_method, marked_windows.candidates)
    self.log.f(
        "switching to profile %d: %d of %d saved windows open, concealing %s",
        switch.number,
        #marked_windows.match_result.matches,
        #marked_windows.arrangement.windows,
        inspect_on_one_line(concealment)
    )
    local window_by_id = track_windows.index_by_id(windows)
    local failures = concatenate_lists.concatenate(
        earlier_failures,
        conceal_windows.apply(concealment, window_by_id)
    )
    self.state = profile_state.with_active_profile_number(self.state, switch.number)
    self:write_state()
    self:refresh_menu()
    if not switch.has_layout then
        hs.alert.show(switch.name)
        self:finish_switch(switch, failures)
        return
    end
    retained_timers.after(
        self.settings.timing.window_settle_seconds,
        self.watchdog:continue(function()
            self:restore_profile_layout(
                switch,
                marked_windows.arrangement,
                marked_windows.match_result,
                window_by_id,
                failures
            )
        end)
    )
end

---Opens the new windows of the missing records, brings the windows to their recorded places, shows
---the recorded desktops and removes the desktops beyond the numbers of the arrangement.
---@param switch RunningSwitch
---@param arrangement Arrangement
---@param match_result WindowMatchResult
---@param window_by_id table<integer, table> the hs.window of each window id of the switch
---@param earlier_failures string[] the failures of the way into view and of the concealment
function ProfileController:restore_profile_layout(
    switch,
    arrangement,
    match_result,
    window_by_id,
    earlier_failures
)
    self:open_missing_windows(
        switch.number,
        match_result.unmatched_records,
        function(new_window_failures, new_matches)
            self:restore_matched_windows(
                switch.number,
                arrangement,
                concatenate_lists.concatenate(match_result.matches, new_matches),
                window_by_id,
                switch.busy_text,
                function(restore_failures, desktops_to_show)
                    extra_desktops.show_desktops_and_remove_extra_ones(
                        arrangement,
                        desktops_to_show,
                        self:extra_desktops_context(),
                        function(desktop_failures)
                            self:finish_switch(
                                switch,
                                concatenate_lists.concatenate(
                                    earlier_failures,
                                    new_window_failures,
                                    restore_failures,
                                    desktop_failures
                                )
                            )
                        end
                    )
                end
            )
        end
    )
end

function ProfileController:deactivate_profile()
    if self:refuse_while_busy() then
        return
    end
    if not self.state.active_profile_number then
        return
    end
    self:capture_active_arrangement()
    self.state = profile_state.with_active_profile_number(self.state, nil)
    self:update_numbers_of_profile_0()
    self:refresh_menu()
    hs.alert.show("No desktop profile")
end

---@param number integer
function ProfileController:deactivate_profile_if_active(number)
    if self.state.active_profile_number ~= number then
        local name = profile_state.profile_or_default(self.state, number).name
        hs.alert.show(name .. " is not active")
        return
    end
    self:deactivate_profile()
end

---Deactivates the active profile, or activates the profile, which restores the layout of the
---active profile while it is paused.
---@param number integer
function ProfileController:toggle_profile(number)
    if self.state.active_profile_number == number and not self.state.is_active_profile_paused then
        self:deactivate_profile()
    else
        self:activate_profile(number)
    end
end

---@param number integer
---@param name string
function ProfileController:rename_profile(number, name)
    self.state = profile_state.with_profile_name(self.state, number, name)
    self:write_state()
    self:refresh_menu()
end

function ProfileController:prompt_rename_active_profile()
    local number = self.state.active_profile_number
    if not number then
        return
    end
    local current_name = profile_state.profile_or_default(self.state, number).name
    hs.focus()
    local button, name = hs.dialog.textPrompt(
        string.format("Rename profile %d", number),
        "The name shows in the menu bar item and in the alert of a switch.",
        current_name,
        "Rename",
        "Cancel"
    )
    if button == "Rename" and name:match("%S") then
        self:rename_profile(number, name)
    end
end

---Removes the records of every monitor configuration of the profile, after the user agrees.
---An active profile stays active and records the windows from its next update on.
---@param number integer
function ProfileController:clear_profile(number)
    if self:refuse_while_busy() then
        return
    end
    local name = profile_state.profile_or_default(self.state, number).name
    if not profile_state.has_arrangements(self.state, number) then
        hs.alert.show(name .. " has no saved layout")
        return
    end
    hs.focus()
    local button = hs.dialog.blockAlert(
        string.format("Clear %s?", name),
        "The profile forgets the desktops and windows it saved for every monitor configuration."
            .. " Its name and its application numbers stay.",
        "Clear",
        "Cancel",
        "warning"
    )
    if button ~= "Clear" then
        return
    end
    retained_timers.stop(self.save_timer)
    self.state = profile_state.clear_arrangements(self.state, number)
    self:write_state()
    self:refresh_menu()
    if self.state.active_profile_number == number then
        hs.alert.show(name .. " is cleared and records the windows from now on")
        self:schedule_save()
    else
        hs.alert.show(name .. " is cleared")
    end
end

---@return ListedApplication[] the applications with a window that the window filter sees
function ProfileController:list_window_applications()
    local applications, seen = {}, {}
    for _, window in ipairs(self.window_filter:getWindows()) do
        local application = window:application()
        local bundle_id = track_windows.bundle_id_of(application)
        if application and not seen[bundle_id] then
            seen[bundle_id] = true
            table.insert(
                applications,
                { bundle_id = bundle_id, app_name = application:name() or bundle_id }
            )
        end
    end
    return applications
end

---The next update of the active profile records the windows of a newly managed application and
---forgets those of an application that macOS manages now.
---@param pool AppPool
function ProfileController:set_app_pool(pool)
    self.state = profile_state.with_app_pool(self.state, pool)
    self:write_state()
    self:schedule_save()
end

---@return HighlightColors the colors of the search: the setting, under the colors that the window
---of the colors chose
function ProfileController:current_highlight_colors()
    return highlight_colors.apply(
        self.settings.search_highlight_colors,
        self.state.highlight_colors
    )
end

---Opens the window that picks the colors of the search, or brings it to the front.
function ProfileController:open_color_window()
    if self.color_window then
        color_window.bring_to_front(self.color_window)
        return
    end
    self.color_window = color_window.open({
        read_colors = function()
            return self:current_highlight_colors()
        end,
        read_base = function()
            return self.settings.search_highlight_colors
        end,
        set_colors = function(chosen)
            self.state = profile_state.with_highlight_colors(self.state, chosen)
            self:write_state()
        end,
        on_closed = function()
            self.color_window = nil
        end,
    })
end

---Opens the window that changes the shortcuts of every tool, or brings it to the front.
function ProfileController:open_shortcut_window()
    if self.shortcut_window then
        shortcut_window.bring_to_front(self.shortcut_window)
        return
    end
    self.shortcut_window = shortcut_window.open(self.shortcuts, function()
        self.shortcut_window = nil
    end)
end

---Opens the window that chooses the managed applications, or brings it to the front.
---Each tick applies at once, so that several ticks need no reopening.
function ProfileController:open_app_pool_window()
    if self.app_pool_window then
        app_pool_window.bring_to_front(self.app_pool_window)
        return
    end
    self.app_pool_window = app_pool_window.open({
        read_pool = function()
            return self.state.app_pool
        end,
        list_choices = function()
            return app_pool.list_choices(self.state.app_pool, self:list_window_applications())
        end,
        set_mode = function(mode)
            self:set_app_pool(app_pool.with_mode(self.state.app_pool, mode))
        end,
        set_listed = function(bundle_id, app_name, is_listed)
            self:set_app_pool(
                app_pool.with_listed(self.state.app_pool, bundle_id, app_name, is_listed)
            )
        end,
        on_closed = function()
            self.app_pool_window = nil
        end,
    })
end

---@param matching string
function ProfileController:set_monitor_matching(matching)
    self:capture_active_arrangement()
    self.state = profile_state.with_monitor_matching(self.state, matching)
    self:write_state()
    self:refresh_menu()
    hs.alert.show("Same monitor configuration by " .. monitor_matching.label_of(matching):lower())
end

---@return Profile the active profile, or profile 0 while no profile is active, whose application
---numbers hold
function ProfileController:read_numbering_profile()
    return profile_state.profile_or_default(
        self.state,
        profile_state.find_numbering_profile_number(self.state)
    )
end

---Gives the default numbers again after a change of the application numbers.
---While a switch runs, the state is written alone, because the update at the end of the switch
---gives the defaults.
function ProfileController:apply_numbers_change()
    if self.is_switch_or_restore_running then
        self:write_state()
    else
        self:update_records_and_numbers()
    end
end

---Gives the number to the application in the active profile, or in profile 0 while no profile is
---active, as the user chose.
---@param app_number integer
---@param bundle_id string
---@param app_name string
function ProfileController:choose_app_number(app_number, bundle_id, app_name)
    local number = profile_state.find_numbering_profile_number(self.state)
    local profile = profile_state.profile_or_default(self.state, number)
    self.state = profile_state.with_app_numbers(
        self.state,
        number,
        app_numbers.choose(profile.app_numbers, app_number, bundle_id, app_name)
    )
    self:write_state()
    hs.alert.show(string.format("%s is number %d in %s", app_name, app_number, profile.name))
end

---Returns the number to the defaults of the active profile, or of profile 0 while no profile is
---active, and gives the defaults again.
---@param app_number integer
function ProfileController:release_app_number(app_number)
    local number = profile_state.find_numbering_profile_number(self.state)
    local profile = profile_state.profile_or_default(self.state, number)
    self.state = profile_state.with_app_numbers(
        self.state,
        number,
        app_numbers.release(profile.app_numbers, app_number)
    )
    self:apply_numbers_change()
end

---Drops every number of the active profile, or of profile 0 while no profile is active, also the
---numbers that the user chose, and gives the default numbers again.
---Nothing happens while the list shows, so that a slip during a press keeps the chosen numbers.
function ProfileController:reset_app_numbers()
    if self.app_number_list:is_open() then
        return
    end
    local number = profile_state.find_numbering_profile_number(self.state)
    self.state = profile_state.with_app_numbers(self.state, number, {})
    self:apply_numbers_change()
    local name = profile_state.profile_or_default(self.state, number).name
    hs.alert.show(name .. " has the default application numbers")
end

---@param app_number integer
---@param name_or_bundle_id string
function ProfileController:number_running_application(app_number, name_or_bundle_id)
    local application = hs.application.get(name_or_bundle_id)
    if not application then
        notify(string.format("No running application is named %q", name_or_bundle_id))
        return
    end
    self:choose_app_number(
        app_number,
        track_windows.bundle_id_of(application),
        application:name() or name_or_bundle_id
    )
end

---@param bundle_id string
---@return integer[] the windows of the application that some profile recorded
function ProfileController:list_recorded_window_ids_of_application(bundle_id)
    local window_ids = {}
    for _, record in ipairs(profile_state.list_all_records(self.state)) do
        if record.bundle_id == bundle_id and record.window_id then
            table.insert(window_ids, record.window_id)
        end
    end
    return window_ids
end

---Runs a press of the list or the search that takes time, with the text as the busy message.
---While a switch, a restore or another press runs, the press gives "Desktop Manager is still
---switching" and does nothing, so that the message of that work stays and Mission Control opens
---for one of them alone.
---@param text string
---@param press fun(on_pressed: fun(error_message: string|nil))
---@param on_done fun(error_message: string|nil)
function ProfileController:run_press(text, press, on_done)
    if self:is_work_running() then
        on_done(STILL_SWITCHING_MESSAGE)
        return
    end
    self.is_press_running = true
    local work_number = self.watchdog:start()
    self:show_busy_message(text)
    press(function(error_message)
        if not self.watchdog:stop(work_number) then
            return
        end
        self.is_press_running = false
        self:end_busy_message()
        on_done(error_message)
    end)
end

---@return boolean whether a switch, a restore or a press of the list or the search runs
function ProfileController:is_work_running()
    return self.is_switch_or_restore_running or self.is_press_running
end

---Shows "Desktop Manager is still switching" while a switch, a restore or a press runs, so that a
---profile shortcut or a selection of the list or the search does nothing and the message of that
---work stays.
---@return boolean whether the action is refused
function ProfileController:refuse_while_busy()
    if self:is_work_running() then
        hs.alert.show(STILL_SWITCHING_MESSAGE)
        return true
    end
    return false
end

---Records the desktop that a press showed as the desktop that its screen shows and as the screen of
---the focus, in the arrangement of the active profile for the monitor configuration of the press.
---A change of monitors during the press, or before the next save, then restores that desktop.
---@param configuration_key string
---@param slot_key string
---@param desktop_number integer
function ProfileController:record_shown_desktop(configuration_key, slot_key, desktop_number)
    local number = profile_state.find_profile_number_to_update(self.state)
    local state = number
        and profile_state.with_shown_desktop(
            self.state,
            number,
            configuration_key,
            slot_key,
            desktop_number
        )
    if not state then
        return
    end
    self.state = state
    self:write_state()
end

---Shows the desktop through Mission Control for a press of the list or the search, and then runs
---`after_shown` inside the press, so that the message and the refusal of other work hold until it
---ends, as during the wait until accessibility reaches a window.
---A desktop that shows already needs no press.
---The arrangement of the active profile records the desktop that the press showed.
---A chosen window lets the press focus another window of its application first, as
---`mission_control_desktops.show_space` says.
---@param space_id integer
---@param after_shown AfterShown|nil
---@param on_done fun(error_message: string|nil)
---@param chosen_window ChosenWindow|nil the window that the press brings to the front
function ProfileController:show_space(space_id, after_shown, on_done, chosen_window)
    local function run_after_shown(on_finished)
        if after_shown then
            after_shown(on_finished)
        else
            on_finished(nil)
        end
    end
    if read_desktops.is_space_active(space_id) then
        run_after_shown(on_done)
        return
    end
    local configuration = self:read_monitor_configuration()
    local location = locate_desktops.locate_space(read_desktops.read_desktop_layout(), space_id)
    local slot = location
        and monitor_configuration.find_slot_of_screen(configuration, location.screen.screen_uuid)
    local text = slot
            and busy_message.describe_showing_desktop(location.desktop_number, slot.slot_key)
        or "Showing another desktop… please wait"
    self:run_press(text, function(on_pressed)
        mission_control_desktops.show_space(space_id, self.settings.timing, function(error_message)
            if error_message then
                on_pressed(error_message)
                return
            end
            if slot then
                self:record_shown_desktop(configuration.key, slot.slot_key, location.desktop_number)
            end
            run_after_shown(on_pressed)
        end, chosen_window)
    end, on_done)
end

---@return AppNumberListContext
function ProfileController:app_number_list_context()
    return {
        settings = self.settings,
        window_filter = self.window_filter,
        window_inventory = self.window_inventory,
        hidden_states = self.hidden_states,
        preview_loader = self.preview_loader,
        read_numbering_profile = function()
            return self:read_numbering_profile()
        end,
        list_recorded_window_ids_of_application = function(bundle_id)
            return self:list_recorded_window_ids_of_application(bundle_id)
        end,
        refresh_window_inventory = function()
            self:refresh_window_inventory(nil)
        end,
        refuse_while_busy = function()
            return self:refuse_while_busy()
        end,
        read_switcher_context = function()
            return self:switcher_context()
        end,
        report_failures = function(failures)
            self:report_failures(failures)
        end,
    }
end

---@return SwitcherContext the presses of the list and the search, through this controller
function ProfileController:switcher_context()
    return {
        timing = self.settings.timing,
        show_space = function(space_id, after_shown, on_done, chosen_window)
            self:show_space(space_id, after_shown, on_done, chosen_window)
        end,
        run_press = function(text, press, on_done)
            self:run_press(text, press, on_done)
        end,
        refuse_while_busy = function()
            return self:refuse_while_busy()
        end,
    }
end

---@return table<integer, boolean> the ids of the windows that the window filter lists now
function ProfileController:list_filter_window_ids()
    return track_windows.index_ids(self.window_filter:getWindows())
end

---Lists the windows that accessibility does not reach again, in the background.
---@param on_done fun()|nil
function ProfileController:refresh_window_inventory(on_done)
    window_inventory.refresh(self.window_inventory, function()
        return self:list_filter_window_ids()
    end, on_done)
end

---Shows the panel of the search of the windows, unless it shows already.
function ProfileController:open_window_search()
    if self.search_panel then
        return
    end
    local opened_at = hs.timer.secondsSinceEpoch()
    local hidden = hidden_application_filter.read_hidden_applications(
        self.settings.hidden_application_windows,
        self.hidden_states
    )
    ---@param known_window_ids table<integer, boolean> the windows of the window filter
    local function list_unreached_windows(known_window_ids)
        return hidden_application_filter.keep_shown_unreached_windows(
            hidden,
            window_inventory.list_unreached_windows(self.window_inventory, known_window_ids)
        )
    end
    local all_filter_windows = self.window_filter:getWindows()
    self.search_panel = search_windows.open({
        filter_windows = hidden_application_filter.list_search_windows(hidden, all_filter_windows),
        unreached_windows = list_unreached_windows(track_windows.index_ids(all_filter_windows)),
        refresh_unreached_windows = function(on_done)
            self:refresh_window_inventory(function()
                on_done(
                    list_unreached_windows(self:list_filter_window_ids()),
                    self.window_inventory.last_update_started_at
                )
            end)
        end,
        app_numbers = self:read_numbering_profile().app_numbers,
        overlay_settings = {
            font_size = self.settings.list_font_size,
            preview_size = self.settings.preview_size,
            highlight_colors = self:current_highlight_colors(),
        },
        switcher = self:switcher_context(),
        preview_loader = self.preview_loader,
        on_closed = function()
            self.search_panel = nil
        end,
        report_failures = function(messages)
            self:report_failures(messages)
        end,
        opened_at = opened_at,
        log = self.log,
    })
end

---The shortcut of the search shows the panel, and closes it while it shows.
function ProfileController:toggle_window_search()
    if self.search_panel then
        search_windows.close(self.search_panel)
        return
    end
    self:open_window_search()
end

---The method that each action of a URL runs.
---@type table<string, fun(controller: ProfileController, command: Command)>
local URL_ACTION_HANDLERS = {
    [url_command.ACTIVATE] = function(controller, command)
        controller:activate_profile(command.profile_number)
    end,
    [url_command.TOGGLE] = function(controller, command)
        controller:toggle_profile(command.profile_number)
    end,
    [url_command.DEACTIVATE] = function(controller, command)
        if command.profile_number then
            controller:deactivate_profile_if_active(command.profile_number)
        else
            controller:deactivate_profile()
        end
    end,
    [url_command.RENAME] = function(controller, command)
        controller:rename_profile(command.profile_number, command.name)
    end,
    [url_command.CYCLE_MONITOR_MATCHING] = function(controller)
        controller:set_monitor_matching(
            monitor_matching.next_after(controller.state.monitor_matching)
        )
    end,
    [url_command.NUMBER_APP] = function(controller, command)
        controller:number_running_application(command.app_number, command.app)
    end,
    [url_command.RELEASE_APP_NUMBER] = function(controller, command)
        controller:release_app_number(command.app_number)
    end,
    [url_command.RESET_APP_NUMBERS] = function(controller)
        controller:reset_app_numbers()
    end,
    [url_command.SAVE] = function(controller)
        controller:capture_active_arrangement()
    end,
    [url_command.CLEAR] = function(controller, command)
        controller:clear_profile(command.profile_number)
    end,
    [url_command.SEARCH_WINDOWS] = function(controller)
        controller:open_window_search()
    end,
}

---@param params table<string, string>
function ProfileController:run_url_command(params)
    local command, error_message = url_command.parse(params, {
        profile_count = self.settings.profile_count,
        app_number_count = self.settings.app_number_count,
    })
    if not command then
        notify(error_message)
        return
    end
    local handle = URL_ACTION_HANDLERS[command.action]
    if handle then
        handle(self, command)
    end
end

---Unhiding an application shows all its windows.
---During a switch, the windows that the profile entered keeps out of sight are minimized again.
---After an unhide that the user makes, the next capture records the windows in sight.
---@param application table an hs.application
function ProfileController:handle_application_unhidden(application)
    if not self.is_switch_or_restore_running or not application then
        return
    end
    for _, window in ipairs(application:allWindows()) do
        local window_id = window:id()
        if window_id and self.window_ids_out_of_sight[window_id] and not window:isMinimized() then
            window:minimize()
        end
    end
end

---@return ExtraDesktopsContext the context of the desktops to show and the desktops to remove
function ProfileController:extra_desktops_context()
    return {
        timing = self.settings.timing,
        log = self.log,
        read_monitor_configuration = function()
            return self:read_monitor_configuration()
        end,
        known_windows = self.known_windows,
        window_inventory = self.window_inventory,
        read_app_pool = function()
            return self.state.app_pool
        end,
        list_filter_window_ids = function()
            return self:list_filter_window_ids()
        end,
        show_busy_message = function(text)
            self:show_busy_message(text)
        end,
        continue = function(callback)
            return self.watchdog:continue(callback)
        end,
    }
end

---The window among the windows of the ids that keeps their desktop at the check right before a
---removal, as `extra_desktops.find_window_that_keeps_desktop` says.
---@param window_ids integer[]
---@return integer|nil
function ProfileController:find_window_that_keeps_desktop(window_ids)
    return extra_desktops.find_window_that_keeps_desktop(window_ids, self:extra_desktops_context())
end

---@param window_id integer
---@return boolean whether the window keeps its desktop at the check right before a removal
function ProfileController:does_window_keep_desktop(window_id)
    return self:find_window_that_keeps_desktop({ window_id }) ~= nil
end

---Waits for macOS to settle the screens, and restarts the wait while a switch, a restore or a press
---runs, so that the change is restored once that work has ended.
function ProfileController:start_screen_timer()
    retained_timers.stop(self.screen_timer)
    self.screen_timer = retained_timers.after(self.settings.timing.screen_settle_seconds, function()
        self.screen_timer = nil
        if self:is_work_running() then
            self:start_screen_timer()
            return
        end
        self.screen_signature = read_screens.read_signature()
        self:restore_after_screens_changed()
    end)
end

---macOS reports a change of the screen parameters also when the Dock changes size, and such a
---change leaves the signature of the screens as it was.
---After a change, the windows of the active profile go back to their places, and the empty desktops
---beyond the number of each display go away.
---Without an active profile, a change leaves the windows and the desktops to macOS.
function ProfileController:handle_screens_changed()
    if self.screen_timer == nil and read_screens.read_signature() == self.screen_signature then
        return
    end
    if self.screen_timer == nil and not self.state.active_profile_number then
        self.screen_signature = read_screens.read_signature()
        return
    end
    self.are_saves_suspended = true
    retained_timers.stop(self.save_timer)
    if profile_state.find_profile_number_to_update(self.state) and not self:is_work_running() then
        self:show_busy_message(MONITORS_CHANGED_MESSAGE)
    end
    self:start_screen_timer()
end

---Restores the arrangement of the active profile for the monitor configuration after a change, or
---removes the empty desktops beyond the kept numbers when the profile has no layout for it.
---A profile deactivated while the monitors settled leaves everything to macOS.
---The restore conceals no window and opens no new window, because the layout predates the windows
---that the user opened under the old configuration.
function ProfileController:restore_after_screens_changed()
    local number = profile_state.find_profile_number_to_update(self.state)
    if not number then
        self.are_saves_suspended = false
        self:close_busy_message()
        self:schedule_save()
        return
    end
    local configuration = self:read_monitor_configuration()
    local saved_arrangement = profile_state.find_arrangement(self.state, number, configuration.key)
    self.is_switch_or_restore_running = true
    local work_number = self.watchdog:start()
    local function finish(failures)
        if not self:end_switch_or_restore_work(work_number) then
            return
        end
        self:report_failures(failures)
        self:resume_saves()
    end
    local name = profile_state.profile_or_default(self.state, number).name
    if not saved_arrangement then
        self:close_busy_message()
        hs.alert.show(
            string.format(
                "%s has no layout for %s yet, so the windows stay where macOS put them",
                name,
                configuration.key
            )
        )
        extra_desktops.remove_extra_desktops(
            self.state.desktop_counts.kept,
            nil,
            self:extra_desktops_context(),
            finish
        )
        return
    end
    local busy_text = string.format("Arranging %s for %s… please wait", name, configuration.key)
    window_inventory.refresh_from_now(
        self.window_inventory,
        function()
            return self:list_filter_window_ids()
        end,
        self.watchdog:continue(function()
            local arrangement =
                app_pool.keep_managed_records(self.state.app_pool, saved_arrangement)
            local windows =
                self.known_windows:list_managed(profile_state.list_recorded_window_ids(arrangement))
            local unreached = self.known_windows:list_unreached_managed(windows)
            local match_result = self:match_with_unreached(arrangement, windows, unreached)
            local windows_to_reach = reach_plan.keep_windows_of_ids(
                unreached,
                reach_plan.select_misplaced(
                    unreached,
                    match_result.matches,
                    configuration,
                    read_desktops.read_desktop_layout()
                )
            )
            self:bring_into_view(arrangement, windows_to_reach, function(into_view_failures)
                self:show_busy_message(busy_text)
                self:restore_open_windows(
                    number,
                    saved_arrangement,
                    busy_text,
                    function(restore_failures, desktops_to_show)
                        extra_desktops.show_desktops_and_remove_extra_ones(
                            arrangement,
                            desktops_to_show,
                            self:extra_desktops_context(),
                            function(desktop_failures)
                                finish(
                                    concatenate_lists.concatenate(
                                        into_view_failures,
                                        restore_failures,
                                        desktop_failures
                                    )
                                )
                            end
                        )
                    end
                )
            end)
        end)
    )
end

---Prints what the tool reads of the screens, desktops and windows, without changing anything.
function ProfileController:print_diagnostics()
    local hammerspoon_lines = diagnostic_lines.describe_hammerspoon()
    local menu_choice_lines = diagnostic_lines.describe_menu_choices(self.state)
    local configuration = self:read_monitor_configuration()
    local screen_lines =
        diagnostic_lines.describe_screens(configuration, self.settings.builtin_screen_name_patterns)
    local desktop_lines =
        diagnostic_lines.describe_desktops(configuration, self.state.desktop_counts.kept)
    local active_number = self.state.active_profile_number
    local active_arrangement = active_number
        and profile_state.find_arrangement(self.state, active_number, configuration.key)
    local profile_lines = diagnostic_lines.describe_profile(self.state, active_arrangement)
    local app_number_lines = diagnostic_lines.describe_app_numbers(self:read_numbering_profile())
    local window_lines = diagnostic_lines.describe_windows(
        self.state,
        self.settings.profile_count,
        configuration.key,
        active_arrangement,
        self.known_windows,
        self.window_filter
    )
    local lines = concatenate_lists.concatenate(
        hammerspoon_lines,
        menu_choice_lines,
        screen_lines,
        desktop_lines,
        profile_lines,
        app_number_lines,
        window_lines
    )
    print(table.concat(lines, "\n"))
end

---@return RegisteredAction[]
function ProfileController:list_shortcut_actions()
    return shortcut_actions.list(self.settings.profile_count, self.settings.app_number_count, {
        toggle_profile = function(number)
            self:toggle_profile(number)
        end,
        deactivate_profile = function()
            self:deactivate_profile()
        end,
        clear_profile = function(number)
            self:clear_profile(number)
        end,
        press_app_number = function(app_number, binding)
            self.app_number_list:press(app_number, binding)
        end,
        reset_app_numbers = function()
            self:reset_app_numbers()
        end,
        toggle_window_search = function()
            self:toggle_window_search()
        end,
    })
end

function ProfileController:start_watchers()
    local filter = hs.window.filter
    self.window_filter:subscribe({
        [filter.windowCreated] = function()
            self:schedule_save()
        end,
        [filter.windowDestroyed] = function()
            self:schedule_save()
        end,
        [filter.windowMoved] = function()
            self:schedule_save()
        end,
        [filter.windowMinimized] = function()
            self:schedule_save()
        end,
        [filter.windowUnminimized] = function()
            self:schedule_save()
        end,
        [filter.windowTitleChanged] = function()
            self:schedule_save()
        end,
    })
    table.insert(
        self.watchers,
        hs.screen.watcher
            .new(function()
                self:handle_screens_changed()
            end)
            :start()
    )
    table.insert(
        self.watchers,
        hs.spaces.watcher
            .new(function()
                self:schedule_save()
                self:refresh_window_inventory(nil)
            end)
            :start()
    )
    table.insert(
        self.watchers,
        hs.application.watcher
            .new(function(_, event, application)
                hidden_application_filter.update_hidden_states(
                    self.hidden_states,
                    event,
                    application
                )
                if event == hs.application.watcher.unhidden then
                    self:handle_application_unhidden(application)
                elseif event == hs.application.watcher.terminated and application then
                    self.preview_loader:forget_app_icon(track_windows.bundle_id_of(application))
                end
            end)
            :start()
    )
    table.insert(
        self.watchers,
        retained_timers.every(self.settings.timing.periodic_save_seconds, function()
            self:schedule_save()
            self:refresh_window_inventory(nil)
        end)
    )
end

---Pauses the active profile at the first start of Hammerspoon soon after the start of macOS, and
---names the pause in the console, also when the state file kept it from an earlier start.
---The state file keeps the start of macOS that this start saw, so that a later start under the same
---start of macOS pauses nothing.
---@param macos_start_time integer|nil the start of macOS in seconds since 1970, or nil when unknown
---@param seconds_since_macos_start number
function ProfileController:pause_at_start(macos_start_time, seconds_since_macos_start)
    local number = self.state.active_profile_number
    local pause_seconds = self.settings.pause_after_macos_start_seconds
    local is_due = profile_pause.is_due_at_start(
        self.state,
        macos_start_time,
        seconds_since_macos_start,
        pause_seconds
    )
    local is_new_macos_start = macos_start_time ~= nil
        and macos_start_time ~= self.state.last_seen_macos_start_time
    if is_new_macos_start then
        self.state = profile_state.with_last_seen_macos_start_time(self.state, macos_start_time)
    end
    if is_due then
        self.state = profile_state.with_active_profile_paused(self.state)
        self.log.i(
            profile_pause.describe_start_pause(number, seconds_since_macos_start, pause_seconds)
        )
    elseif self.state.is_active_profile_paused then
        self.log.i(profile_pause.describe_kept_pause(number))
    end
    if is_due or is_new_macos_start then
        self:write_state()
    end
end

---@return integer|nil the start of macOS in seconds since 1970, or nil when sysctl gives none
local function read_macos_start_time()
    local boot_time_output = hs.execute(MACOS_START_TIME_COMMAND)
    return profile_pause.parse_macos_start_time(boot_time_output)
end

---@param unchecked_settings Settings
---@param shortcuts ShortcutCenter|nil the center of the shortcuts of every tool, or nil for a
---center of this tool alone
---@return ProfileController
function profile_controller.start(unchecked_settings, shortcuts)
    local renamed_settings, renaming_lines = settings_check.replace_old_values(unchecked_settings)
    local settings, message = settings_check.check(renamed_settings)
    if not settings then
        error(message, 2)
    end
    local controller = setmetatable({
        settings = settings,
        log = hs.logger.new("desktop_mgr", "info"),
        watchers = {},
        is_switch_or_restore_running = false,
        is_press_running = false,
        are_saves_suspended = false,
        window_ids_out_of_sight = {},
        window_inventory = window_inventory.new(),
        hidden_states = {},
    }, ProfileController)
    for _, line in ipairs(renaming_lines) do
        controller.log.w(line)
    end
    controller.watchdog = work_watchdog.new(settings.timing, function()
        controller:stop_unfinished_work()
    end)
    controller.preview_loader = window_previews.new_loader(settings, controller.log)
    local state, warning =
        state_file.read(settings.state_file_path, settings.initial_monitor_matching)
    controller.state = state
    if warning then
        controller.log.w(warning)
        notify(warning)
    end
    controller:pause_at_start(
        read_macos_start_time(),
        hs.timer.absoluteTime() / NANOSECONDS_PER_SECOND
    )
    controller.screen_signature = read_screens.read_signature()
    controller.window_filter = track_windows.new_filter()
    controller.known_windows = list_known_windows.new(
        controller.window_filter,
        controller.window_inventory,
        function()
            return controller.state.app_pool
        end
    )
    controller.app_number_list = app_number_list.new(controller:app_number_list_context())
    controller.menubar = hs.menubar.new()
    controller:refresh_menu()
    controller.shortcuts = shortcuts or shortcut_center.new(nil)
    controller.shortcuts:register(controller:list_shortcut_actions())
    hs.urlevent.bind(settings.url_event_name, function(_, params)
        controller:run_url_command(params)
    end)
    controller:start_watchers()
    controller:refresh_window_inventory(nil)
    if not controller.state.active_profile_number then
        controller:schedule_save()
    end
    if not hs.accessibilityState() then
        notify("Hammerspoon needs the Accessibility permission to move windows")
    end
    return controller
end

return profile_controller
