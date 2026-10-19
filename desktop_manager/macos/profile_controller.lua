local app_numbers = require("desktop_manager.core.app_numbers")
local app_pool = require("desktop_manager.core.app_pool")
local app_pool_window = require("desktop_manager.macos.app_pool_window")
local app_switcher = require("desktop_manager.macos.app_switcher")
local arrangement_capture = require("desktop_manager.core.arrangement_capture")
local busy_message = require("desktop_manager.macos.busy_message")
local color_window = require("desktop_manager.macos.color_window")
local concealment_method = require("desktop_manager.core.concealment_method")
local conceal_windows = require("desktop_manager.macos.conceal_windows")
local deep_copy = require("desktop_manager.core.deep_copy")
local desktop_counts = require("desktop_manager.core.desktop_counts")
local keyboard_modifiers = require("desktop_manager.macos.keyboard_modifiers")
local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")
local highlight_colors = require("desktop_manager.core.highlight_colors")
local list_layout = require("desktop_manager.core.list_layout")
local list_sizing = require("desktop_manager.core.list_sizing")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local missing_windows = require("desktop_manager.core.missing_windows")
local mission_control_desktops = require("desktop_manager.macos.mission_control_desktops")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local move_windows = require("desktop_manager.macos.move_windows")
local new_windows = require("desktop_manager.macos.new_windows")
local preview_method = require("desktop_manager.core.preview_method")
local profile_state = require("desktop_manager.core.profile_state")
local profile_switch = require("desktop_manager.core.profile_switch")
local reach_plan = require("desktop_manager.core.reach_plan")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local restore_plan = require("desktop_manager.core.restore_plan")
local restore_windows = require("desktop_manager.macos.restore_windows")
local retained_timers = require("desktop_manager.macos.retained_timers")
local search_windows = require("desktop_manager.macos.search_windows")
local shortcut_center = require("keyboard_shortcuts.macos.shortcut_center")
local shortcut_window = require("keyboard_shortcuts.macos.shortcut_window")
local state_file = require("desktop_manager.macos.state_file")
local status_menu = require("desktop_manager.macos.status_menu")
local switch_list = require("desktop_manager.core.switch_list")
local switch_overlay = require("desktop_manager.macos.switch_overlay")
local title_overflow = require("desktop_manager.core.title_overflow")
local track_windows = require("desktop_manager.macos.track_windows")
local url_command = require("desktop_manager.core.url_command")
local window_matching = require("desktop_manager.core.window_matching")
local window_inventory = require("desktop_manager.macos.window_inventory")
local window_previews = require("desktop_manager.macos.window_previews")

local profile_controller = {}

local NOTIFICATION_TITLE = "Desktop Manager"
local FAILURE_ALERT_SECONDS = 8
local STILL_SWITCHING_MESSAGE = "Desktop Manager is still switching"
local MONITORS_CHANGED_MESSAGE = "Monitors changed, waiting for macOS… please wait"

---Owns the state, the hotkeys, the URL event, the menu bar item and the watchers.
---`is_busy` is true while a switch or a restore moves windows, and then no arrangement is saved.
---`is_showing_desktop` is true while a press of the list or the search shows a desktop through
---Mission Control, unhides an application or opens a window, and then no switch starts.
---@class ProfileController
---@field settings Settings
---@field state State
---@field log table an hs.logger
---@field window_filter table an hs.window.filter
---@field menubar table an hs.menubar
---@field shortcuts ShortcutCenter
---@field watchers table[]
---@field is_busy boolean
---@field is_showing_desktop boolean
---@field work_number integer the number of the last switch, restore or press, which a watchdog
---that stops it changes, so that its later steps end nothing
---@field watchdog_timer table|nil
---@field busy_message BusyMessage|nil the message on the screens while a switch, a restore or a
---press of the list or the search runs
---@field busy_message_text string|nil the text of the message
---@field app_pool_window AppPoolWindow|nil the window that chooses the managed applications
---@field are_saves_suspended boolean
---@field save_timer table|nil
---@field screen_timer table|nil
---@field screen_signature string the screens that the last arrangement was restored for
---@field window_ids_out_of_sight table<integer, boolean> the windows that the last switch took out
---of sight
---@field switch_session SwitchSession|nil the list of applications while it shows
---@field search_panel SearchPanel|nil the panel of the search of the windows while it shows
---@field window_inventory WindowInventory the windows that accessibility does not reach
---@field reached_windows table<integer, table> the hs.window of each window that a reach moved into
---view, until the window filter lists it
---@field are_snapshots_stopped boolean whether a slow snapshot stopped the snapshots until a reload
---@field hidden_states HiddenStates whether each application that the list or the search asked
---about is hidden

---The list of numbered applications that a press of their modifiers with a number opens.
---@class SwitchSession
---@field entries AppNumber[]
---@field applications SwitchApplication[]
---@field window_by_id table<integer, table> the hs.window of each window id in the list
---@field unreached_by_id table<integer, ServerWindow> the windows of the list that accessibility
---does not reach
---@field selection SwitchSelection|nil
---@field images SwitchImages the icons and the previews that the list shows
---@field displays SwitchDisplay[] the displays from left to right, for the columns per display
---@field overlay table|nil the hs.canvas of the list
---@field event_tap table|nil the hs.eventtap that watches the modifiers and Escape
local ProfileController = {}
ProfileController.__index = ProfileController

---@param message string
local function notify(message)
    hs.notify.new({ title = NOTIFICATION_TITLE, informativeText = message }):send()
end

---@generic T
---@param first T[]
---@param second T[]
---@return T[]
local function concatenate(first, second)
    local joined = { table.unpack(first) }
    for _, item in ipairs(second) do
        table.insert(joined, item)
    end
    return joined
end

---@param value any
---@return string
local function inspect_on_one_line(value)
    return hs.inspect(value, { newline = " ", indent = "" })
end

---@param desktop_number integer
---@param slot_key string
---@return string the busy message while Mission Control shows the desktop
local function describe_showing(desktop_number, slot_key)
    return string.format("Showing desktop %d of %s… please wait", desktop_number, slot_key)
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
---@return OpenWindow[] open_windows
---@return LiveWindow[] live_windows the same windows with their titles, for the matching
local function describe_open_windows(windows)
    local open_windows, live_windows = {}, {}
    for _, window in ipairs(windows) do
        local window_id = window:id()
        if window_id then
            local application = window:application()
            local bundle_id = track_windows.bundle_id_of(application)
            table.insert(open_windows, {
                window_id = window_id,
                bundle_id = bundle_id,
                is_minimized = window:isMinimized(),
                is_app_hidden = application ~= nil and application:isHidden(),
            })
            table.insert(
                live_windows,
                { window_id = window_id, bundle_id = bundle_id, title = window:title() or "" }
            )
        end
    end
    return open_windows, live_windows
end

---@param arrangement Arrangement|nil
---@return integer[] the window ids that the arrangement records
local function list_recorded_window_ids(arrangement)
    local window_ids = {}
    for _, record in ipairs(arrangement and arrangement.windows or {}) do
        if record.window_id then
            table.insert(window_ids, record.window_id)
        end
    end
    return window_ids
end

---Some windows of macOS report the window id 0, such as one of Control Center.
---@param window table an hs.window
---@return boolean
local function has_valid_id(window)
    local window_id = window:id()
    return window_id ~= nil and window_id > 0
end

---@param windows table[] hs.window objects
---@return table[] the windows of the applications that the desktop manager manages
function ProfileController:keep_managed_windows(windows)
    local pool = self.state.app_pool
    if app_pool.holds_every_application(pool) then
        return windows
    end
    local kept = {}
    for _, window in ipairs(windows) do
        if app_pool.is_managed(pool, track_windows.bundle_id_of(window:application())) then
            table.insert(kept, window)
        end
    end
    return kept
end

---@param arrangement Arrangement
---@return Arrangement a copy without the records of the applications that the desktop manager
---leaves to macOS
function ProfileController:keep_managed_records(arrangement)
    local kept = {}
    for key, value in pairs(arrangement) do
        kept[key] = value
    end
    kept.windows = app_pool.keep_managed(self.state.app_pool, arrangement.windows)
    return kept
end

---The windows of the managed applications that the tool knows.
---@param window_ids integer[]
---@return table[] hs.window objects
function ProfileController:list_known_windows(window_ids)
    return self:keep_managed_windows(self:list_all_known_windows(window_ids))
end

---The windows of the window filter, and the windows of `window_ids` that the filter does not list.
---The filter drops a window whose subrole is not AXStandardWindow when the window hides or
---minimizes, as the window of Calendar does while Calendar is hidden.
---@param window_ids integer[]
---@return table[] hs.window objects
function ProfileController:list_all_known_windows(window_ids)
    local windows = {}
    for _, window in ipairs(self.window_filter:getWindows()) do
        if has_valid_id(window) then
            table.insert(windows, window)
        end
    end
    local listed = track_windows.index_by_id(windows)
    local reached_ids = {}
    for window_id in pairs(self.reached_windows) do
        table.insert(reached_ids, window_id)
    end
    table.sort(reached_ids)
    for _, window_id in ipairs(reached_ids) do
        local window = self.reached_windows[window_id]
        if listed[window_id] then
            self.reached_windows[window_id] = nil
        elseif window:id() == window_id then
            listed[window_id] = window
            table.insert(windows, window)
        else
            self.reached_windows[window_id] = nil
        end
    end
    local missing = {}
    for _, window_id in ipairs(window_ids) do
        if not listed[window_id] then
            missing[window_id] = true
        end
    end
    if next(missing) == nil then
        return windows
    end
    local known = { table.unpack(windows) }
    for _, window in ipairs(hs.window.allWindows()) do
        local window_id = window:id()
        if window_id and missing[window_id] then
            missing[window_id] = nil
            table.insert(known, window)
        end
    end
    return known
end

---Gives the records of a window that its application reopened the id of the new window, in every
---profile, under the policy that matches titles.
---A reopened window is an open window that no profile recorded, of the same application and with
---the same title as a recorded window that no longer exists.
---@param windows table[] the hs.window objects that the tool knows
function ProfileController:rename_reopened_windows(windows)
    if
        self.settings.missing_window_policy ~= missing_window_policy.MATCH_TITLE_OR_OPEN_NEW_WINDOW
    then
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
    local closed_records, is_listed = {}, {}
    for _, record in ipairs(profile_state.list_all_records(self.state)) do
        local key = string.format("%s#%s", record.bundle_id, tostring(record.window_id))
        if
            record.window_id
            and not is_listed[key]
            and not open_ids[record.window_id]
            and not read_desktops.find_window_space_id(record.window_id)
        then
            is_listed[key] = true
            table.insert(closed_records, record)
        end
    end
    local match_result =
        window_matching.match_records_to_reopened_windows(closed_records, unrecorded_windows)
    if #match_result.matches == 0 then
        return
    end
    local renames = {}
    for _, match in ipairs(match_result.matches) do
        table.insert(renames, {
            bundle_id = match.record.bundle_id,
            old_window_id = match.record.window_id,
            new_window_id = match.window_id,
        })
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

---The windows of the managed applications that the window server listed on a desktop out of view
---at the last refresh of the inventory, and that Hammerspoon has not seen.
---@param known_windows table[] hs.window objects
---@return ServerWindow[]
function ProfileController:list_unreached_managed_windows(known_windows)
    local unreached = {}
    for _, window in
        ipairs(
            window_inventory.list_unreached_windows(
                self.window_inventory,
                track_windows.index_ids(known_windows)
            )
        )
    do
        if app_pool.is_managed(self.state.app_pool, window.bundle_id) then
            table.insert(unreached, window)
        end
    end
    return unreached
end

---@param window_id integer
---@return table|nil an hs.window
function ProfileController:find_window(window_id)
    for _, window in ipairs(self.window_filter:getWindows()) do
        if window:id() == window_id then
            return window
        end
    end
    return hs.window.get(window_id)
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
function ProfileController:capture_active_arrangement()
    local number = self.state.active_profile_number
    if not number or self.is_busy or self.are_saves_suspended then
        return
    end
    local configuration = self:read_monitor_configuration()
    local known_windows = self:list_known_windows(
        list_recorded_window_ids(
            profile_state.find_arrangement(self.state, number, configuration.key)
        )
    )
    self:rename_reopened_windows(known_windows)
    local previous = profile_state.find_arrangement(self.state, number, configuration.key)
    local observations, observed_ids = observe_windows(known_windows)
    local previous_records =
        app_pool.keep_managed(self.state.app_pool, previous and previous.windows or {})
    local previous_by_id = {}
    for _, record in ipairs(previous_records) do
        if record.window_id then
            previous_by_id[record.window_id] = record
        end
    end
    for _, window in ipairs(self:list_unreached_managed_windows(known_windows)) do
        if not observed_ids[window.window_id] then
            observed_ids[window.window_id] = true
            local previous_record = previous_by_id[window.window_id]
            table.insert(observations, {
                window_id = window.window_id,
                bundle_id = window.bundle_id,
                app_name = window.app_name,
                title = (window.title == "" and previous_record) and previous_record.title
                    or window.title,
                space_id = window.space_id,
                frame = window.frame,
                is_out_of_sight = false,
            })
        end
    end
    for _, record in ipairs(previous_records) do
        if record.window_id and not observed_ids[record.window_id] then
            local space_id = read_desktops.find_window_space_id(record.window_id)
            if space_id then
                table.insert(observations, {
                    window_id = record.window_id,
                    bundle_id = record.bundle_id,
                    app_name = record.app_name,
                    title = record.title,
                    space_id = space_id,
                    frame = nil,
                    is_out_of_sight = record.is_out_of_sight,
                })
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
    self.state = profile_state.with_app_numbers(
        self.state,
        number,
        app_numbers.update_defaults(
            profile_state.profile_or_default(self.state, number).app_numbers,
            arrangement,
            configuration,
            self.settings.app_number_count
        )
    )
    self:write_state()
end

---Gives profile 0 its default numbers from the windows open now, because it records no windows.
---A default number of profile 0 therefore stays while its application has a window open.
function ProfileController:update_numbers_of_profile_0()
    local configuration = self:read_monitor_configuration()
    local observations = observe_windows(self:list_known_windows({}))
    local open_windows = arrangement_capture.capture(
        configuration,
        read_desktops.read_desktop_layout(),
        observations,
        nil
    )
    local number = profile_state.NO_PROFILE_NUMBER
    self.state = profile_state.with_app_numbers(
        self.state,
        number,
        app_numbers.update_defaults(
            profile_state.profile_or_default(self.state, number).app_numbers,
            open_windows,
            configuration,
            self.settings.app_number_count
        )
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
function ProfileController:capture_numbering_profile()
    self:track_desktop_counts()
    if self.state.active_profile_number then
        self:capture_active_arrangement()
    else
        self:update_numbers_of_profile_0()
    end
end

function ProfileController:schedule_save()
    if self.is_busy or self.are_saves_suspended then
        return
    end
    retained_timers.stop(self.save_timer)
    self.save_timer = retained_timers.after(self.settings.timing.save_delay_seconds, function()
        self.save_timer = nil
        if not self.is_busy and not self.are_saves_suspended then
            self:capture_numbering_profile()
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
    if self.screen_timer and self.state.active_profile_number then
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
        return window_by_id[window_id] or self:find_window(window_id)
    end
    local live_states = {}
    for _, match in ipairs(matches) do
        local window = find_window(match.window_id)
        if window then
            local application = window:application()
            live_states[match.window_id] = {
                bundle_id = track_windows.bundle_id_of(application),
                is_minimized = window:isMinimized(),
                is_app_hidden = application ~= nil and application:isHidden(),
            }
        end
    end
    local plan = restore_plan.plan(
        arrangement,
        self:read_monitor_configuration(),
        read_desktops.read_desktop_layout(),
        matches,
        live_states
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
        is_current = self:watch_current_work(),
    }
    restore_windows.apply(
        plan,
        context,
        self:continue_work(function(failures)
            on_done(failures, plan.shown_desktops)
        end)
    )
end

---Matches the records of the arrangement against the known windows and the windows that
---accessibility does not reach, so that a record of an unseen window takes that window, and no new
---window opens for it.
---@param arrangement Arrangement
---@param known_windows table[] hs.window objects
---@param unreached ServerWindow[]
---@return WindowMatchResult
---@return OpenWindow[] open_windows the known and the unseen windows, for the marks of a switch
function ProfileController:match_with_unseen(arrangement, known_windows, unreached)
    local open_windows, live_windows = describe_open_windows(known_windows)
    for _, window in ipairs(unreached) do
        table.insert(open_windows, {
            window_id = window.window_id,
            bundle_id = window.bundle_id,
            is_minimized = false,
            is_app_hidden = false,
        })
        table.insert(
            live_windows,
            { window_id = window.window_id, bundle_id = window.bundle_id, title = window.title }
        )
    end
    local match_result = window_matching.match_records_to_open_windows(
        self.settings.match_windows_by,
        self.settings.missing_window_policy,
        arrangement.windows,
        live_windows
    )
    return match_result, open_windows
end

---Restores the open windows of an arrangement, and returns the records that found no window and
---the recorded desktops to show.
---@param number integer
---@param saved_arrangement Arrangement
---@param busy_text string
---@param on_done fun(failures: string[], unmatched: WindowRecord[], desktops: ScreenDesktop[])
function ProfileController:restore_open_windows(number, saved_arrangement, busy_text, on_done)
    local arrangement = self:keep_managed_records(saved_arrangement)
    local windows = self:list_known_windows(list_recorded_window_ids(arrangement))
    local match_result =
        self:match_with_unseen(arrangement, windows, self:list_unreached_managed_windows(windows))
    self:restore_matched_windows(
        number,
        arrangement,
        match_result.matches,
        track_windows.index_by_id(windows),
        busy_text,
        function(failures, desktops_to_show)
            on_done(failures, match_result.unmatched_records, desktops_to_show)
        end
    )
end

---Gives each record in sight whose window no longer exists a new window of its application, and
---writes the new window ids into the records of every profile.
---A new window opens on the desktop that shows, and the restore moves it to its recorded desktop
---by its frame and its id, through the new matches that `on_done` receives.
---A record whose window sits on a desktop that Hammerspoon has not seen keeps that window.
---@param number integer
---@param unmatched_records WindowRecord[]
---@param on_done fun(failures: string[], new_matches: WindowMatch[])
function ProfileController:open_missing_windows(number, unmatched_records, on_done)
    local missing_records = {}
    for _, record in ipairs(unmatched_records) do
        local space_id = record.window_id and read_desktops.find_window_space_id(record.window_id)
        if record.is_out_of_sight then
            self.log.f(
                "%s window %q is recorded out of sight and gone",
                record.app_name,
                record.title
            )
        elseif space_id then
            self.log.f(
                "%s window %q stays on desktop %d, where Hammerspoon has not seen it",
                record.app_name,
                record.title,
                space_id
            )
        else
            table.insert(missing_records, record)
        end
    end
    local plan = missing_windows.plan(
        missing_records,
        self:read_monitor_configuration(),
        read_desktops.read_desktop_layout()
    )
    for _, record in ipairs(plan.unplaced_records) do
        self.log.f("%s window %q has no recorded desktop here", record.app_name, record.title)
    end
    local session = new_windows.start_session(self.settings.timing)
    local failures, renames, new_matches = {}, {}, {}
    local function open_next(index)
        local missing_window = plan.missing_windows[index]
        if not missing_window then
            if #renames > 0 then
                self.state = profile_state.rename_windows(self.state, renames)
                self:write_state()
            end
            on_done(failures, new_matches)
            return
        end
        local record = missing_window.record
        session:provide_window(
            record,
            self:continue_work(function(window, error_message)
                if not window then
                    table.insert(failures, error_message)
                else
                    self.log.f(
                        "profile %d: %s window %q is now window %d",
                        number,
                        record.app_name,
                        record.title,
                        window:id()
                    )
                    table.insert(new_matches, { window_id = window:id(), record = record })
                    if record.window_id then
                        table.insert(renames, {
                            bundle_id = record.bundle_id,
                            old_window_id = record.window_id,
                            new_window_id = window:id(),
                        })
                    end
                end
                open_next(index + 1)
            end)
        )
    end
    open_next(1)
end

---@param screen ScreenDesktops
---@return integer|nil the desktop that the screen shows, or nil while it shows a space in full
---screen
local function find_view_space_id(screen)
    for _, space_id in ipairs(screen.space_ids) do
        if space_id == screen.active_space_id then
            return space_id
        end
    end
    return nil
end

---Moves a window that came into view and that accessibility did not reach there back to its
---desktop by its id, because the switch can neither minimize it nor set its frame, and reports it.
---@param windows ServerWindow[] the windows that accessibility did not reach
---@param desktop_numbers table<integer, integer> the desktop of each window before its move
---@param failures string[]
---@param on_done fun()
function ProfileController:move_unreached_windows_back(windows, desktop_numbers, failures, on_done)
    if #windows == 0 then
        on_done()
        return
    end
    local moves = {}
    for _, window in ipairs(windows) do
        table.insert(moves, { window_id = window.window_id, space_id = window.space_id })
    end
    move_windows.move_all(
        moves,
        self.settings.timing,
        self:continue_work(function(move_failures)
            local back_failures = {}
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
            on_done()
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
---@param on_done fun(failures: string[])
function ProfileController:reach_windows(windows, on_done)
    if #windows == 0 then
        on_done({})
        return
    end
    self.log.f("moving %d windows into view to reach them", #windows)
    self:show_busy_message("Finding the windows on other desktops… please wait")
    local timing = self.settings.timing
    local desktop_layout = read_desktops.read_desktop_layout()
    local failures, moves, window_by_id, desktop_numbers = {}, {}, {}, {}
    for _, window in ipairs(windows) do
        window_by_id[window.window_id] = window
        local location = arrangement_capture.locate_space(desktop_layout, window.space_id)
        local view_space_id = location and find_view_space_id(location.screen)
        if view_space_id then
            desktop_numbers[window.window_id] = location.desktop_number
            table.insert(moves, { window_id = window.window_id, space_id = view_space_id })
        else
            table.insert(
                failures,
                string.format(
                    "%s window %q stays out of reach, because its screen shows no desktop",
                    window.app_name,
                    window.title
                )
            )
        end
    end
    move_windows.move_all(
        moves,
        timing,
        self:continue_work(function(move_failures)
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
                self:continue_work(function(reached)
                    local unreached = {}
                    for _, window in ipairs(moved) do
                        if reached[window.window_id] then
                            self.reached_windows[window.window_id] = reached[window.window_id]
                        else
                            table.insert(unreached, window)
                        end
                    end
                    self:move_unreached_windows_back(
                        unreached,
                        desktop_numbers,
                        failures,
                        function()
                            on_done(failures)
                        end
                    )
                end)
            )
        end)
    )
end

---@param windows ServerWindow[]
---@param window_ids integer[]
---@return ServerWindow[] the windows of the ids, each once, in the order of the windows
local function keep_windows_of_ids(windows, window_ids)
    local is_chosen, kept = {}, {}
    for _, window_id in ipairs(window_ids) do
        is_chosen[window_id] = true
    end
    for _, window in ipairs(windows) do
        if is_chosen[window.window_id] then
            table.insert(kept, window)
        end
    end
    return kept
end

---Shows the recorded desktop, or desktop 1, of each screen that shows a space in full screen,
---because a window moved there by its id or by its frame would join the window in full screen.
---@param arrangement Arrangement|nil
---@param on_done fun(failures: string[])
function ProfileController:leave_full_screen(arrangement, on_done)
    self:show_desktops(
        restore_plan.plan_exits_from_full_screen(
            arrangement,
            self:read_monitor_configuration(),
            read_desktops.read_desktop_layout()
        ),
        on_done
    )
end

---Starts the watchdog of a switch, a restore or a press in Mission Control, which stops the work
---when it has not ended after `busy_watchdog_seconds`, as after an error in a timer of a step.
---@return integer the number of the work, which `stop_watchdog` takes
function ProfileController:start_watchdog()
    self.work_number = self.work_number + 1
    retained_timers.stop(self.watchdog_timer)
    self.watchdog_timer = retained_timers.after(
        self.settings.timing.busy_watchdog_seconds,
        function()
            self.watchdog_timer = nil
            self:stop_unfinished_work()
        end
    )
    return self.work_number
end

---@return fun(): boolean whether the switch, the restore or the press that runs now still runs, and
---the watchdog has not stopped it
function ProfileController:watch_current_work()
    local work_number = self.work_number
    return function()
        return work_number == self.work_number
    end
end

---Wraps a callback of a step of the work that runs now, so that the callback does nothing once the
---watchdog has stopped that work.
---@param callback function
---@return function
function ProfileController:continue_work(callback)
    local is_current = self:watch_current_work()
    return function(...)
        if is_current() then
            callback(...)
        end
    end
end

---@param work_number integer
---@return boolean whether the work still runs, and the watchdog has not stopped it
function ProfileController:stop_watchdog(work_number)
    if work_number ~= self.work_number then
        return false
    end
    retained_timers.stop(self.watchdog_timer)
    self.watchdog_timer = nil
    return true
end

---Ends a switch, a restore or a press that did not finish, so that the next one can start.
---The steps that still run act no further, because the number of the work has changed and the
---openings of Mission Control have stopped.
function ProfileController:stop_unfinished_work()
    self.work_number = self.work_number + 1
    local message = string.format(
        "Desktop Manager stopped a switch that did not finish within %g seconds",
        self.settings.timing.busy_watchdog_seconds
    )
    self.log.e(message)
    mission_control_desktops.stop_openings()
    self.is_busy = false
    self.is_showing_desktop = false
    self:end_busy_message()
    self:report_failures({ message })
    self:resume_saves()
end

function ProfileController:activate_profile(number)
    if self.is_busy or self.is_showing_desktop then
        hs.alert.show(STILL_SWITCHING_MESSAGE)
        return
    end
    if self.state.active_profile_number == number then
        return
    end
    local started_at = hs.timer.secondsSinceEpoch()
    self:capture_active_arrangement()
    self.is_busy = true
    local work_number = self:start_watchdog()
    retained_timers.stop(self.save_timer)
    local name = profile_state.profile_or_default(self.state, number).name
    self:show_busy_message(string.format("Arranging %s… please wait", name))
    self:switch_to_profile(number, started_at, work_number)
end

---Conceals the windows that the profile does not keep, and restores the windows it records.
---The unseen windows that the switch acts on come into view by their ids first.
---@param number integer
---@param started_at number
---@param work_number integer
function ProfileController:switch_to_profile(number, started_at, work_number)
    local configuration = self:read_monitor_configuration()
    local name = profile_state.profile_or_default(self.state, number).name
    local busy_text = string.format("Arranging %s… please wait", name)
    local function read_arrangement()
        return profile_state.find_arrangement(self.state, number, configuration.key)
    end
    local function list_windows()
        local windows = self:list_known_windows(list_recorded_window_ids(read_arrangement()))
        self:rename_reopened_windows(windows)
        return windows
    end
    local has_layout = read_arrangement() ~= nil
    ---@param known_windows table[]
    ---@param unreached ServerWindow[]
    ---@return Arrangement arrangement
    ---@return WindowMatchResult match_result
    ---@return SwitchCandidate[] candidates
    local function mark_windows(known_windows, unreached)
        local arrangement = self:keep_managed_records(
            read_arrangement()
                or { monitor_configuration_key = configuration.key, monitors = {}, windows = {} }
        )
        local match_result, open_windows =
            self:match_with_unseen(arrangement, known_windows, unreached)
        local candidates = has_layout
                and profile_switch.mark_kept_windows(open_windows, match_result.matches)
            or profile_switch.mark_kept_windows_for_new_profile(
                open_windows,
                profile_state.index_recorded_windows(self.state)
            )
        return arrangement, match_result, candidates
    end
    local function finish(failures)
        if not self:stop_watchdog(work_number) then
            return
        end
        self.is_busy = false
        self:end_busy_message()
        self:schedule_save()
        self.log.f(
            "profile %d is active after %.1f seconds, with %d problems",
            number,
            hs.timer.secondsSinceEpoch() - started_at,
            #failures
        )
        self:report_failures(failures)
    end
    local function conceal_and_restore(earlier_failures)
        self:show_busy_message(busy_text)
        local windows = list_windows()
        local arrangement, match_result, candidates =
            mark_windows(windows, self:list_unreached_managed_windows(windows))
        self.window_ids_out_of_sight = {}
        for _, candidate in ipairs(candidates) do
            if not candidate.is_kept then
                self.window_ids_out_of_sight[candidate.window_id] = true
            end
        end
        local concealment =
            profile_switch.plan_concealment(self.settings.concealment_method, candidates)
        self.log.f(
            "switching to profile %d: %d of %d saved windows open, concealing %s",
            number,
            #match_result.matches,
            #arrangement.windows,
            inspect_on_one_line(concealment)
        )
        local window_by_id = track_windows.index_by_id(windows)
        local failures =
            concatenate(earlier_failures, conceal_windows.apply(concealment, window_by_id))
        self.state = profile_state.with_active_profile_number(self.state, number)
        self:write_state()
        self:refresh_menu()
        if not has_layout then
            hs.alert.show(name)
            finish(failures)
            return
        end
        retained_timers.after(
            self.settings.timing.window_settle_seconds,
            self:continue_work(function()
                self:open_missing_windows(
                    number,
                    match_result.unmatched_records,
                    function(opening_failures, new_matches)
                        self:restore_matched_windows(
                            number,
                            arrangement,
                            concatenate(match_result.matches, new_matches),
                            window_by_id,
                            busy_text,
                            function(restore_failures, desktops_to_show)
                                self:show_desktops_and_remove_extra_ones(
                                    arrangement,
                                    desktops_to_show,
                                    function(desktop_failures)
                                        finish(
                                            concatenate(
                                                concatenate(failures, opening_failures),
                                                concatenate(restore_failures, desktop_failures)
                                            )
                                        )
                                    end
                                )
                            end
                        )
                    end
                )
            end)
        )
    end
    local windows = list_windows()
    local unreached = self:list_unreached_managed_windows(windows)
    local arrangement, match_result, candidates = mark_windows(windows, unreached)
    local window_ids_to_reach =
        reach_plan.select_concealed(self.settings.concealment_method, unreached, candidates)
    if has_layout then
        window_ids_to_reach = concatenate(
            reach_plan.select_misplaced(
                unreached,
                match_result.matches,
                configuration,
                read_desktops.read_desktop_layout()
            ),
            window_ids_to_reach
        )
    end
    local windows_to_reach = keep_windows_of_ids(unreached, window_ids_to_reach)
    if not has_layout and #windows_to_reach == 0 then
        conceal_and_restore({})
        return
    end
    self:leave_full_screen(arrangement, function(exit_failures)
        self:reach_windows(windows_to_reach, function(reach_failures)
            conceal_and_restore(concatenate(exit_failures, reach_failures))
        end)
    end)
end

function ProfileController:deactivate_profile()
    if self.is_busy then
        hs.alert.show(STILL_SWITCHING_MESSAGE)
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

---@param number integer
function ProfileController:toggle_profile(number)
    if self.state.active_profile_number == number then
        self:deactivate_profile()
    else
        self:activate_profile(number)
    end
end

---@param number integer
---@param name string
function ProfileController:rename_profile(number, name)
    self.state = profile_state.rename_profile(self.state, number, name)
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
    if self.is_busy then
        hs.alert.show(STILL_SWITCHING_MESSAGE)
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

---Opens the window that changes the shortcuts of every utility, or brings it to the front.
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
    if self.is_busy then
        -- The update at the end of the switch gives the defaults.
        self:write_state()
    else
        self:capture_numbering_profile()
    end
end

---Drops every number of the active profile, or of profile 0 while no profile is active, also the
---numbers that the user chose, and gives the default numbers again.
---Nothing happens while the list shows, so that a slip during a press keeps the chosen numbers.
function ProfileController:reset_app_numbers()
    if self.switch_session then
        return
    end
    local number = profile_state.find_numbering_profile_number(self.state)
    self.state = profile_state.with_app_numbers(self.state, number, {})
    if self.is_busy then
        -- The update at the end of the switch gives the defaults.
        self:write_state()
    else
        self:capture_numbering_profile()
    end
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

---@param session SwitchSession
---@return SwitchView
local function describe_switch_rows(session)
    return {
        lines = switch_list.describe_lines(
            session.applications,
            session.selection,
            switch_overlay.MAX_TITLE_LENGTH
        ),
    }
end

---@param session SwitchSession
---@return SwitchView
local function describe_switch_columns(session)
    return {
        groups = switch_list.describe_application_columns(session.applications, session.selection),
    }
end

---@param session SwitchSession
---@return SwitchView
local function describe_switch_columns_per_display(session)
    return {
        groups = switch_list.describe_display_columns(
            session.applications,
            session.selection,
            session.displays
        ),
    }
end

local SWITCH_VIEW_BUILDERS = {
    [list_layout.ROWS] = describe_switch_rows,
    [list_layout.COLUMNS] = describe_switch_columns,
    [list_layout.COLUMNS_PER_DISPLAY] = describe_switch_columns_per_display,
}

---Opens the list of numbered applications with the window of the number selected, or moves the
---selection while the list shows.
---A number that the active profile, or profile 0 while no profile is active, gives to no
---application passes its keys through to the application in front while the list is closed.
---@param app_number integer
---@param binding ShortcutBinding the shortcut of the number and its hs.hotkey
function ProfileController:press_app_number(app_number, binding)
    local session = self.switch_session
    if session then
        session.selection = switch_list.press(session.applications, session.selection, app_number)
        if session.overlay then
            switch_overlay.update(
                session.overlay,
                self:describe_switch_view(session),
                session.images
            )
        end
        return
    end
    local entries = profile_state.profile_or_default(
        self.state,
        profile_state.find_numbering_profile_number(self.state)
    ).app_numbers
    if not app_numbers.find_by_number(entries, app_number) then
        binding.hotkey:disable()
        hs.eventtap.keyStroke(binding.shortcut.modifiers, binding.shortcut.key, 0)
        binding.hotkey:enable()
        return
    end
    self:open_switch_list(entries, app_number, binding.shortcut.modifiers)
end

---@param session SwitchSession
---@return SwitchView
function ProfileController:describe_switch_view(session)
    return SWITCH_VIEW_BUILDERS[self.settings.list_layout](session)
end

---@return SwitchListSettings the settings that the list and the search of the windows share
function ProfileController:describe_list_settings()
    return {
        preview_size = self.settings.preview_size,
        font_size = self.settings.list_font_size,
        sizing = self.settings.list_sizing,
        title_overflow = self.settings.title_overflow,
        title_line_count = self.settings.title_line_count,
    }
end

---@return SwitchDisplay[] the displays in the order in which they stand from left to right
function ProfileController:list_displays_from_left()
    local screens = read_screens.describe_screens(self.settings.builtin_screen_name_patterns)
    table.sort(screens, function(first, second)
        return first.frame.x < second.frame.x
    end)
    local displays = {}
    for _, screen in ipairs(screens) do
        table.insert(displays, { screen_uuid = screen.uuid, name = screen.name })
    end
    return displays
end

---Shows the list while the user holds the modifiers, and goes to the selection when they are
---released, or at once when they were released before the event tap started.
---@param entries AppNumber[]
---@param app_number integer
---@param modifiers string[] the modifiers of the shortcut that opened the list, which the user
---holds
function ProfileController:open_switch_list(entries, app_number, modifiers)
    local hidden = app_switcher.read_hidden_applications(
        self.settings.hidden_application_windows,
        self.hidden_states
    )
    local all_filter_windows = self.window_filter:getWindows()
    local filter_windows = app_switcher.keep_shown_filter_windows(hidden, all_filter_windows)
    local unreached_windows = app_switcher.keep_shown_unreached_windows(
        hidden,
        window_inventory.list_unreached_windows(
            self.window_inventory,
            track_windows.index_ids(all_filter_windows)
        )
    )
    self:refresh_window_inventory(nil)
    local screen_uuid_by_space = {}
    for _, screen in ipairs(read_desktops.read_desktop_layout().screens) do
        for _, space_id in ipairs(screen.space_ids) do
            screen_uuid_by_space[space_id] = screen.screen_uuid
        end
    end
    local applications, window_by_id = {}, {}
    for _, entry in ipairs(entries) do
        local application, windows = app_switcher.describe_application(
            entry,
            filter_windows,
            unreached_windows,
            screen_uuid_by_space,
            hidden
        )
        table.insert(applications, application)
        for window_id, window in pairs(windows) do
            window_by_id[window_id] = window
        end
    end
    local unreached_by_id = {}
    for _, window in ipairs(unreached_windows) do
        unreached_by_id[window.window_id] = window
    end
    local app_icons = {}
    for _, entry in ipairs(entries) do
        app_icons[entry.bundle_id] = window_previews.read_app_icon(entry.bundle_id)
    end
    local session = {
        entries = entries,
        applications = applications,
        window_by_id = window_by_id,
        unreached_by_id = unreached_by_id,
        selection = switch_list.press(applications, nil, app_number),
        images = { app_icons = app_icons, previews = {} },
        displays = self:list_displays_from_left(),
        modifiers = modifiers,
    }
    self.switch_session = session
    if not keyboard_modifiers.are_held(modifiers) then
        self:go_to_switch_selection()
        return
    end
    session.overlay = switch_overlay.show(
        self:describe_switch_view(session),
        session.images,
        self:describe_list_settings()
    )
    local event_types = hs.eventtap.event.types
    session.event_tap = hs.eventtap
        .new({ event_types.flagsChanged, event_types.keyDown }, function(event)
            return self:handle_switch_event(event)
        end)
        :start()
    if not keyboard_modifiers.are_held(modifiers) then
        self:go_to_switch_selection()
        return
    end
    self:load_switch_previews(session)
end

---Takes the snapshots of the windows of a list one at a time, after the list shows, and gives each
---to `on_image` as it comes, under the setting for snapshots.
---A snapshot slower than the time limit stops the snapshots until the next reload, because the
---function behind it once blocked Hammerspoon for two minutes on macOS 27.0.1.
---@param window_ids integer[]
---@param preview_size table the w and h of a preview in points
---@param is_list_shown fun(): boolean
---@param on_image fun(window_id: integer, image: table)
function ProfileController:load_previews(window_ids, preview_size, is_list_shown, on_image)
    if self.settings.preview_method ~= preview_method.BLURRED_SNAPSHOTS then
        return
    end
    window_previews.load_one_at_a_time(window_ids, {
        blur = self.settings.preview_blur,
        preview_size = preview_size,
        time_limit_seconds = self.settings.timing.snapshot_time_limit_seconds,
        is_wanted = function()
            return is_list_shown() and not self.are_snapshots_stopped
        end,
        on_image = on_image,
        on_too_slow = function(seconds)
            self.are_snapshots_stopped = true
            self.log.w(
                string.format(
                    "a snapshot took %.1f seconds, so the list shows icons until the next reload",
                    seconds
                )
            )
        end,
    })
end

---Draws the preview of each window of the list in the place of the icon, as the snapshot comes.
---@param session SwitchSession
function ProfileController:load_switch_previews(session)
    local window_ids = {}
    for _, application in ipairs(session.applications) do
        for _, window in ipairs(application.windows) do
            table.insert(window_ids, window.window_id)
        end
    end
    self:load_previews(window_ids, switch_overlay.read_preview_size(session.overlay), function()
        return self.switch_session == session
    end, function(window_id, image)
        if session.overlay then
            session.images.previews[window_id] = image
            switch_overlay.update(
                session.overlay,
                self:describe_switch_view(session),
                session.images
            )
        end
    end)
end

---Goes to the selection when a modifier of the numbers is released, and closes the list on Escape.
---The work runs after the event tap returns, so that the tap has stopped before Mission Control
---opens to show another desktop.
---@param event table an hs.eventtap.event
---@return boolean whether the event stops here
function ProfileController:handle_switch_event(event)
    local event_types = hs.eventtap.event.types
    if event:getType() == event_types.keyDown then
        if event:getKeyCode() == hs.keycodes.map.escape then
            retained_timers.defer(function()
                self:close_switch_list()
            end)
            return true
        end
        return false
    end
    if not keyboard_modifiers.are_all_in(event:getFlags(), self.switch_session.modifiers) then
        retained_timers.defer(function()
            self:go_to_switch_selection()
        end)
    end
    return false
end

---@return SwitchSession|nil the session that was open
function ProfileController:close_switch_list()
    local session = self.switch_session
    if not session then
        return nil
    end
    self.switch_session = nil
    if session.event_tap then
        session.event_tap:stop()
    end
    if session.overlay then
        switch_overlay.hide(session.overlay)
    end
    return session
end

function ProfileController:go_to_switch_selection()
    local session = self:close_switch_list()
    if not session or not session.selection or self:refuse_while_busy() then
        return
    end
    local entry = app_numbers.find_by_number(session.entries, session.selection.number)
    local window_id = switch_list.find_selected_window_id(session.applications, session.selection)
    local function report(error_message)
        if error_message then
            self:report_failures({ error_message })
        end
    end
    local unreached = window_id and session.unreached_by_id[window_id]
    if unreached then
        app_switcher.reach_window(unreached, self:switcher_context(), report)
        return
    end
    if switch_list.find_application(session.applications, session.selection.number).is_hidden then
        app_switcher.unhide_application(
            entry,
            self:list_recorded_window_ids_of_application(entry.bundle_id),
            self:switcher_context(),
            report
        )
        return
    end
    app_switcher.switch_to_selection(
        entry,
        window_id and session.window_by_id[window_id],
        self:list_recorded_window_ids_of_application(entry.bundle_id),
        self:switcher_context(),
        report
    )
end

---Runs a press of the list or the search that takes time, with the text as the busy message.
---While a switch, a restore or another press runs, the press gives "Desktop Manager is still
---switching" and does nothing, so that the message of that work stays and Mission Control opens
---for one of them alone.
---@param text string
---@param press fun(on_pressed: fun(error_message: string|nil))
---@param on_done fun(error_message: string|nil)
function ProfileController:run_press(text, press, on_done)
    if self.is_busy or self.is_showing_desktop then
        on_done(STILL_SWITCHING_MESSAGE)
        return
    end
    self.is_showing_desktop = true
    local work_number = self:start_watchdog()
    self:show_busy_message(text)
    press(function(error_message)
        if not self:stop_watchdog(work_number) then
            return
        end
        self.is_showing_desktop = false
        self:end_busy_message()
        on_done(error_message)
    end)
end

---Shows "Desktop Manager is still switching" while a switch, a restore or a press runs, so that a
---selection of the list or the search does nothing and the message of that work stays.
---@return boolean whether the selection is refused
function ProfileController:refuse_while_busy()
    if self.is_busy or self.is_showing_desktop then
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
    local number = self.state.active_profile_number
    local arrangement = number
        and profile_state.find_arrangement(self.state, number, configuration_key)
    if not arrangement then
        return
    end
    local recorded = deep_copy.copy(arrangement)
    for _, monitor in ipairs(recorded.monitors) do
        if monitor.slot_key == slot_key then
            monitor.shown_desktop_number = desktop_number
        end
    end
    recorded.focused_slot_key = slot_key
    self.state = profile_state.with_arrangement(self.state, number, recorded)
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
    local location = arrangement_capture.locate_space(read_desktops.read_desktop_layout(), space_id)
    local slot = location
        and monitor_configuration.find_slot_of_screen(configuration, location.screen.screen_uuid)
    local text = slot and describe_showing(location.desktop_number, slot.slot_key)
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

---Lists the windows that accessibility does not reach again, in the background.
---@param on_done fun()|nil
function ProfileController:refresh_window_inventory(on_done)
    window_inventory.refresh(self.window_inventory, function()
        return track_windows.index_ids(self.window_filter:getWindows())
    end, on_done)
end

---Shows the panel of the search of the windows, unless it shows already.
function ProfileController:open_window_search()
    if self.search_panel then
        return
    end
    local hidden = app_switcher.read_hidden_applications(
        self.settings.hidden_application_windows,
        self.hidden_states
    )
    local function list_unreached_windows()
        return app_switcher.keep_shown_unreached_windows(
            hidden,
            window_inventory.list_unreached_windows(
                self.window_inventory,
                track_windows.index_ids(self.window_filter:getWindows())
            )
        )
    end
    self.search_panel = search_windows.open({
        filter_windows = app_switcher.list_search_windows(hidden, self.window_filter:getWindows()),
        unreached_windows = list_unreached_windows(),
        refresh_unreached_windows = function(on_done)
            self:refresh_window_inventory(function()
                on_done(list_unreached_windows())
            end)
        end,
        app_numbers = profile_state.profile_or_default(
            self.state,
            profile_state.find_numbering_profile_number(self.state)
        ).app_numbers,
        overlay_settings = {
            font_size = self.settings.list_font_size,
            preview_size = self.settings.preview_size,
            highlight_colors = self:current_highlight_colors(),
        },
        switcher = self:switcher_context(),
        load_previews = function(window_ids, preview_size, is_list_shown, on_image)
            self:load_previews(window_ids, preview_size, is_list_shown, on_image)
        end,
        on_closed = function()
            self.search_panel = nil
        end,
        report_failures = function(messages)
            self:report_failures(messages)
        end,
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
    if command.action == url_command.ACTIVATE then
        self:activate_profile(command.profile_number)
    elseif command.action == url_command.TOGGLE then
        self:toggle_profile(command.profile_number)
    elseif command.action == url_command.DEACTIVATE and command.profile_number then
        self:deactivate_profile_if_active(command.profile_number)
    elseif command.action == url_command.DEACTIVATE then
        self:deactivate_profile()
    elseif command.action == url_command.RENAME then
        self:rename_profile(command.profile_number, command.name)
    elseif command.action == url_command.CYCLE_MONITOR_MATCHING then
        self:set_monitor_matching(monitor_matching.next_after(self.state.monitor_matching))
    elseif command.action == url_command.NUMBER_APP then
        self:number_running_application(command.app_number, command.app)
    elseif command.action == url_command.RELEASE_APP_NUMBER then
        self:release_app_number(command.app_number)
    elseif command.action == url_command.RESET_APP_NUMBERS then
        self:reset_app_numbers()
    elseif command.action == url_command.SAVE then
        self:capture_active_arrangement()
    elseif command.action == url_command.CLEAR then
        self:clear_profile(command.profile_number)
    elseif command.action == url_command.SEARCH_WINDOWS then
        self:open_window_search()
    end
end

---Unhiding an application shows all its windows.
---During a switch, the windows that the profile entered keeps out of sight are minimized again.
---After an unhide that the user makes, the next capture records the windows in sight.
---@param application table an hs.application
function ProfileController:handle_application_unhidden(application)
    if not self.is_busy or not application then
        return
    end
    for _, window in ipairs(application:allWindows()) do
        local window_id = window:id()
        if window_id and self.window_ids_out_of_sight[window_id] and not window:isMinimized() then
            window:minimize()
        end
    end
end

---A window of an application that the desktop manager leaves to macOS keeps its desktop in every
---state, and a window of a managed application keeps it while it is in sight.
---@param window table an hs.window
---@return boolean
function ProfileController:does_known_window_keep_desktop(window)
    local application = window:application()
    if not app_pool.is_managed(self.state.app_pool, track_windows.bundle_id_of(application)) then
        return true
    end
    return not window:isMinimized() and not (application ~= nil and application:isHidden())
end

---The desktops that hold a window that keeps them from a removal.
---A window that Hammerspoon knows keeps its desktop as `does_known_window_keep_desktop` says.
---A window that the window server listed out of view at the last refresh of the inventory, and that
---Hammerspoon has not seen, keeps its desktop, because it is in sight there.
---A window that macOS lists on several desktops holds none of them.
---@return table<integer, boolean>
function ProfileController:find_occupied_space_ids()
    local occupied = {}
    local known_by_id = track_windows.index_by_id(self:list_all_known_windows({}))
    for window_id, space_id in pairs(self.window_inventory.occupying_windows) do
        if not known_by_id[window_id] then
            occupied[space_id] = true
        end
    end
    for window_id, window in pairs(known_by_id) do
        local space_ids = read_desktops.list_window_space_ids(window_id)
        if #space_ids == 1 and self:does_known_window_keep_desktop(window) then
            occupied[space_ids[1]] = true
        end
    end
    return occupied
end

---The window among those that macOS lists on a desktop that keeps the desktop, at the check right
---before the removal of the desktop, as `does_known_window_keep_desktop` says.
---A window that macOS shows on every desktop keeps none of them.
---A window that Hammerspoon has not seen counts in the plan of the removal alone, through the
---inventory, which also leaves out the small windows and the windows without a Dock icon.
---The windows that the window filter leaves out come from one walk of every window of every
---application, instead of one walk for each window as `hs.window.get` does.
---@param window_ids integer[]
---@return integer|nil
function ProfileController:find_window_that_keeps_desktop(window_ids)
    local known_by_id = track_windows.index_by_id(self:list_all_known_windows({}))
    local all_by_id = nil
    for _, window_id in ipairs(window_ids) do
        if #read_desktops.list_window_space_ids(window_id) == 1 then
            local window = known_by_id[window_id]
            if not window then
                all_by_id = all_by_id or track_windows.index_by_id(hs.window.allWindows())
                window = all_by_id[window_id]
            end
            if window and self:does_known_window_keep_desktop(window) then
                return window_id
            end
        end
    end
    return nil
end

---@param window_id integer
---@return boolean whether the window keeps its desktop at the check right before a removal
function ProfileController:does_window_keep_desktop(window_id)
    return self:find_window_that_keeps_desktop({ window_id }) ~= nil
end

---@param desktop ScreenDesktop
---@return integer|nil the space of the desktop, or of the last desktop of a screen with fewer
local function find_space_id_of(desktop)
    local screen = read_desktops.find_screen_desktops(desktop.screen_uuid)
    return screen and screen.space_ids[math.min(desktop.desktop_number, #screen.space_ids)]
end

---Shows each desktop through Mission Control, in one opening per desktop, because a press on a
---thumbnail closes Mission Control.
---@param desktops ScreenDesktop[]
---@param on_done fun(failures: string[])
function ProfileController:show_desktops(desktops, on_done)
    local failures, index = {}, 0
    local function show_next()
        index = index + 1
        local desktop = desktops[index]
        if not desktop then
            on_done(failures)
            return
        end
        local space_id = find_space_id_of(desktop)
        if not space_id then
            table.insert(failures, string.format("%s has no desktops", desktop.slot_key))
            show_next()
            return
        end
        if not read_desktops.is_space_active(space_id) then
            self:show_busy_message(describe_showing(desktop.desktop_number, desktop.slot_key))
        end
        mission_control_desktops.show_space(
            space_id,
            self.settings.timing,
            self:continue_work(function(error_message)
                if error_message then
                    table.insert(failures, error_message)
                end
                show_next()
            end)
        )
    end
    show_next()
end

---@param screen_uuid string
---@param count_by_slot table<string, integer>
---@return boolean whether the screen shows a desktop beyond the number of its slot
function ProfileController:shows_extra_desktop(screen_uuid, count_by_slot)
    local screen = read_desktops.find_screen_desktops(screen_uuid)
    local slot =
        monitor_configuration.find_slot_of_screen(self:read_monitor_configuration(), screen_uuid)
    local count = slot and count_by_slot[slot.slot_key]
    if not screen or not count then
        return false
    end
    for position, space_id in ipairs(screen.space_ids) do
        if space_id == screen.active_space_id then
            return position > count
        end
    end
    return false
end

---@param edits DesktopEdit[]
---@param removed_count integer
---@param desktop_of_focus ScreenDesktop|nil
---@return string|nil the message of the last opening of Mission Control, nil when it does nothing
local function describe_last_opening(edits, removed_count, desktop_of_focus)
    if #edits == 1 then
        return string.format(
            "Removing %d empty desktops from %s… please wait",
            removed_count,
            edits[1].slot_key
        )
    elseif #edits > 1 then
        return string.format("Removing %d empty desktops… please wait", removed_count)
    end
    if not desktop_of_focus then
        return nil
    end
    local space_id = find_space_id_of(desktop_of_focus)
    if space_id and not read_desktops.is_space_active(space_id) then
        return describe_showing(desktop_of_focus.desktop_number, desktop_of_focus.slot_key)
    end
    return nil
end

---Removes the desktops beyond the number of each slot that do not show and hold no window that
---keeps them, from the end of each screen.
---The removals of every screen and the press on the desktop of the screen of the focus go in one
---opening of Mission Control, because the press closes it.
---A desktop beyond the number that shows on the screen of the focus would stay in view until that
---press, so the desktop of the focus then shows first, in an opening of its own.
---@param count_by_slot table<string, integer> the number of desktops of each slot
---@param desktop_of_focus ScreenDesktop|nil the recorded desktop of the screen of the focus
---@param on_done fun(failures: string[])
function ProfileController:remove_extra_desktops(count_by_slot, desktop_of_focus, on_done)
    local timing = self.settings.timing
    local function find_keeping_window(window_ids)
        return self:find_window_that_keeps_desktop(window_ids)
    end
    local function remove_and_show(failures)
        window_inventory.refresh_from_now(
            self.window_inventory,
            function()
                return track_windows.index_ids(self.window_filter:getWindows())
            end,
            self:continue_work(function()
                local removals = desktop_counts.plan_removals(
                    count_by_slot,
                    self:read_monitor_configuration(),
                    read_desktops.read_desktop_layout(),
                    self:find_occupied_space_ids()
                )
                local edits, removed_count = {}, 0
                for _, removal in ipairs(removals) do
                    if removal.staying_count > 0 then
                        self.log.f(
                            "%s keeps %d desktops beyond its %d, because they show or hold a"
                                .. " window, or lie below one that does, as the empty desktops %s",
                            removal.slot_key,
                            removal.staying_count,
                            removal.count,
                            table.concat(removal.empty_staying_space_ids, ", ")
                        )
                    end
                    if #removal.space_ids > 0 and read_screens.find_screen(removal.screen_uuid) then
                        self.log.f(
                            "removing the empty desktops %s beyond desktop %d of %s",
                            table.concat(removal.space_ids, ", "),
                            removal.count,
                            removal.slot_key
                        )
                        table.insert(edits, {
                            screen_uuid = removal.screen_uuid,
                            slot_key = removal.slot_key,
                            desktops_to_add = 0,
                            space_ids_to_remove = removal.space_ids,
                        })
                        removed_count = removed_count + #removal.space_ids
                    end
                end
                local message = describe_last_opening(edits, removed_count, desktop_of_focus)
                if message then
                    self:show_busy_message(message)
                end
                local finish = self:continue_work(function(edit_failures)
                    on_done(concatenate(failures, edit_failures))
                end)
                local space_id = desktop_of_focus and find_space_id_of(desktop_of_focus)
                if space_id then
                    mission_control_desktops.edit_and_show_space(
                        edits,
                        space_id,
                        find_keeping_window,
                        timing,
                        finish
                    )
                    return
                end
                mission_control_desktops.edit(edits, find_keeping_window, timing, finish)
            end)
        )
    end
    if
        desktop_of_focus and self:shows_extra_desktop(desktop_of_focus.screen_uuid, count_by_slot)
    then
        self:show_desktops({ desktop_of_focus }, remove_and_show)
        return
    end
    remove_and_show({})
end

---Gives the focus to the front window of the screen of the slot, when the focus is on another
---screen, because the last press in Mission Control may have been on another screen.
---@param slot_key string|nil
function ProfileController:focus_screen_of_slot(slot_key)
    local slot = slot_key
        and monitor_configuration.find_slot(self:read_monitor_configuration(), slot_key)
    local screen = slot and read_desktops.find_screen_desktops(slot.screen_uuid)
    if
        not screen
        or read_desktops.read_desktop_layout().focused_space_id == screen.active_space_id
    then
        return
    end
    for _, window in ipairs(hs.window.orderedWindows()) do
        local window_id = window:id()
        if
            window_id
            and window:isStandard()
            and read_desktops.find_window_space_id(window_id) == screen.active_space_id
        then
            window:focus()
            return
        end
    end
    self.log.f("%s shows no window to take the focus", slot_key)
end

---Shows the recorded desktop of each screen, removes the desktops beyond the numbers of the
---arrangement, and shows the desktop of the screen of the focus in the last opening of Mission
---Control, which then has the focus.
---@param arrangement Arrangement
---@param desktops ScreenDesktop[] the desktops to show, the desktop of the screen of the focus last
---@param on_done fun(failures: string[])
function ProfileController:show_desktops_and_remove_extra_ones(arrangement, desktops, on_done)
    local desktop_of_focus = desktops[#desktops]
    local other_desktops = { table.unpack(desktops, 1, math.max(#desktops - 1, 0)) }
    self:show_desktops(other_desktops, function(show_failures)
        self:remove_extra_desktops(
            desktop_counts.count_by_slot(arrangement),
            desktop_of_focus,
            function(removal_failures)
                self:focus_screen_of_slot(arrangement.focused_slot_key)
                on_done(concatenate(show_failures, removal_failures))
            end
        )
    end)
end

---Waits for macOS to settle the screens, and restarts the wait while a switch, a restore or a press
---runs, so that the change is restored once that work has ended.
function ProfileController:start_screen_timer()
    retained_timers.stop(self.screen_timer)
    self.screen_timer = retained_timers.after(self.settings.timing.screen_settle_seconds, function()
        self.screen_timer = nil
        if self.is_busy or self.is_showing_desktop then
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
    if self.state.active_profile_number and not self.is_busy and not self.is_showing_desktop then
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
    local number = self.state.active_profile_number
    if not number then
        self.are_saves_suspended = false
        self:close_busy_message()
        self:schedule_save()
        return
    end
    local configuration = self:read_monitor_configuration()
    local saved_arrangement = profile_state.find_arrangement(self.state, number, configuration.key)
    self.is_busy = true
    local work_number = self:start_watchdog()
    local function finish(failures)
        if not self:stop_watchdog(work_number) then
            return
        end
        self.is_busy = false
        self:end_busy_message()
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
        self:remove_extra_desktops(self.state.desktop_counts.kept, nil, finish)
        return
    end
    local busy_text = string.format("Arranging %s for %s… please wait", name, configuration.key)
    window_inventory.refresh_from_now(
        self.window_inventory,
        function()
            return track_windows.index_ids(self.window_filter:getWindows())
        end,
        self:continue_work(function()
            local arrangement = self:keep_managed_records(saved_arrangement)
            local windows = self:list_known_windows(list_recorded_window_ids(arrangement))
            local unreached = self:list_unreached_managed_windows(windows)
            local match_result = self:match_with_unseen(arrangement, windows, unreached)
            local windows_to_reach = keep_windows_of_ids(
                unreached,
                reach_plan.select_misplaced(
                    unreached,
                    match_result.matches,
                    configuration,
                    read_desktops.read_desktop_layout()
                )
            )
            self:leave_full_screen(arrangement, function(exit_failures)
                self:reach_windows(windows_to_reach, function(reach_failures)
                    self:show_busy_message(busy_text)
                    self:restore_open_windows(
                        number,
                        saved_arrangement,
                        busy_text,
                        function(restore_failures, _, desktops_to_show)
                            self:show_desktops_and_remove_extra_ones(
                                arrangement,
                                desktops_to_show,
                                function(desktop_failures)
                                    finish(
                                        concatenate(
                                            concatenate(exit_failures, reach_failures),
                                            concatenate(restore_failures, desktop_failures)
                                        )
                                    )
                                end
                            )
                        end
                    )
                end)
            end)
        end)
    )
end

---Prints what the tool reads of the screens, desktops and windows, without changing anything.
function ProfileController:print_diagnostics()
    local lines = {}
    local function add(format, ...)
        table.insert(lines, string.format(format, ...))
    end
    add("Hammerspoon %s", tostring(hs.processInfo and hs.processInfo.version))
    add("accessibility permission: %s", tostring(hs.accessibilityState()))
    add("running timers: %d", retained_timers.count_running())
    add("monitor matching: %s", self.state.monitor_matching)
    add("application pool: %s", app_pool.describe(self.state.app_pool))
    local configuration = self:read_monitor_configuration()
    add("monitor configuration: %s", configuration.key)
    for _, screen in
        ipairs(read_screens.describe_screens(self.settings.builtin_screen_name_patterns))
    do
        local slot = monitor_configuration.find_slot_of_screen(configuration, screen.uuid)
        add(
            "  screen %s %q built-in=%s slot=%s",
            screen.uuid,
            screen.name,
            tostring(screen.is_builtin),
            slot.slot_key
        )
    end
    local layout = read_desktops.read_desktop_layout()
    for _, screen in ipairs(layout.screens) do
        local numbered, shown = {}, nil
        for position, space_id in ipairs(screen.space_ids) do
            table.insert(numbered, string.format("%d=%d", position, space_id))
            if space_id == screen.active_space_id then
                shown = tostring(position)
            end
        end
        local slot = monitor_configuration.find_slot_of_screen(configuration, screen.screen_uuid)
        add(
            "  desktops of %s (%s): %s, shown %s",
            screen.screen_uuid,
            slot and slot.slot_key or "no slot",
            table.concat(numbered, " "),
            shown or string.format("space %s", tostring(screen.active_space_id))
        )
    end
    add("focused desktop: %s", tostring(layout.focused_space_id))
    local kept_counts = {}
    for slot_key, count in pairs(self.state.desktop_counts.kept) do
        table.insert(kept_counts, string.format("%s %d", slot_key, count))
    end
    table.sort(kept_counts)
    add("desktops kept per display: %s", table.concat(kept_counts, ", "))
    add("active profile: %s", tostring(self.state.active_profile_number))
    local active_number = self.state.active_profile_number
    local active_layout = active_number
        and profile_state.find_arrangement(self.state, active_number, configuration.key)
    for _, monitor in ipairs(active_layout and active_layout.monitors or {}) do
        add(
            monitor.shown_desktop_number
                    and "profile %d holds %d desktops on %s and shows desktop %d"
                or "profile %d holds %d desktops on %s and records no desktop shown",
            active_number,
            monitor.desktop_count,
            monitor.slot_key,
            monitor.shown_desktop_number
        )
    end
    if active_layout and active_layout.focused_slot_key then
        add("profile %d had the focus on %s", active_number, active_layout.focused_slot_key)
    end
    local numbering_profile = profile_state.profile_or_default(
        self.state,
        profile_state.find_numbering_profile_number(self.state)
    )
    add("application numbers of %s:", numbering_profile.name)
    for _, entry in ipairs(numbering_profile.app_numbers) do
        add(
            "  app number %d: %s %s%s",
            entry.number,
            entry.app_name,
            entry.bundle_id,
            entry.is_chosen_by_user and " (chosen)" or ""
        )
    end
    local records_by_profile = {}
    for number = 1, self.settings.profile_count do
        local arrangement = profile_state.find_arrangement(self.state, number, configuration.key)
        records_by_profile[number] = {}
        for _, record in ipairs(arrangement and arrangement.windows or {}) do
            if record.window_id then
                records_by_profile[number][record.window_id] = record
            end
        end
    end
    local listed = track_windows.index_by_id(self.window_filter:getWindows())
    local active_arrangement = self.state.active_profile_number
        and profile_state.find_arrangement(
            self.state,
            self.state.active_profile_number,
            configuration.key
        )
    local known_windows = self:list_known_windows(list_recorded_window_ids(active_arrangement))
    add("windows out of reach: %d", #self:list_unreached_managed_windows(known_windows))
    for _, window in ipairs(known_windows) do
        local observation = track_windows.observe(window)
        local recorded_states = {}
        for number = 1, self.settings.profile_count do
            local record = records_by_profile[number][observation.window_id]
            if record then
                local sight = record.is_out_of_sight and "out of sight" or "in sight"
                table.insert(recorded_states, string.format("%d %s", number, sight))
            end
        end
        add(
            "  window %s %s %q desktop=%s out-of-sight=%s in-filter=%s recorded=%s",
            tostring(observation.window_id),
            observation.bundle_id,
            observation.title,
            tostring(observation.space_id),
            tostring(observation.is_out_of_sight),
            tostring(listed[observation.window_id] ~= nil),
            table.concat(recorded_states, ", ")
        )
    end
    print(table.concat(lines, "\n"))
end

---The actions of the profiles, the application numbers and the search of the windows, with their
---default shortcuts.
---@return RegisteredAction[]
function ProfileController:list_shortcut_actions()
    local actions = {}
    local profile_modifiers = { "cmd", "alt", "shift" }
    for number = 1, self.settings.profile_count do
        table.insert(actions, {
            id = "profiles.toggle." .. number,
            group = "Profiles",
            title = string.format(
                "Activate profile %d, or deactivate it while it is active",
                number
            ),
            default = { modifiers = profile_modifiers, key = tostring(number) },
            on_press = function()
                self:toggle_profile(number)
            end,
        })
    end
    table.insert(actions, {
        id = "profiles.deactivate",
        group = "Profiles",
        title = "Deactivate the active profile",
        default = { modifiers = profile_modifiers, key = "0" },
        on_press = function()
            self:deactivate_profile()
        end,
    })
    -- Control-Option-Command with a digit is free between the application numbers and the profiles,
    -- and the profile is cleared only after the user agrees in a dialog.
    for number = 1, self.settings.profile_count do
        table.insert(actions, {
            id = "profiles.clear." .. number,
            group = "Profiles",
            title = string.format(
                "Clear profile %d, after a confirmation, so that it forgets its saved layouts",
                number
            ),
            default = { modifiers = { "ctrl", "alt", "cmd" }, key = tostring(number) },
            on_press = function()
                self:clear_profile(number)
            end,
        })
    end
    -- Control-Option takes no shortcut of macOS or of the running applications, while Command
    -- takes the tabs and views of many applications and Command-Shift takes the screenshots.
    local app_modifiers = { "ctrl", "alt" }
    for app_number = 1, self.settings.app_number_count do
        table.insert(actions, {
            id = "app_numbers.press." .. app_number,
            group = "Application numbers",
            title = string.format(
                "Show the windows of application %d, and go to the selection on release",
                app_number
            ),
            default = { modifiers = app_modifiers, key = tostring(app_number) },
            on_press = function(binding)
                self:press_app_number(app_number, binding)
            end,
        })
    end
    table.insert(actions, {
        id = "app_numbers.reset",
        group = "Application numbers",
        title = "Return every application number to the default",
        default = { modifiers = app_modifiers, key = "0" },
        on_press = function()
            self:reset_app_numbers()
        end,
    })
    -- Control-Option-Command-Space takes no shortcut of macOS, whose shortcuts use Space with
    -- Control and with Control-Option for the input sources.
    table.insert(actions, {
        id = "window_search.toggle",
        group = "Window search",
        title = "Show the search of the windows, or close it",
        default = { modifiers = { "ctrl", "alt", "cmd" }, key = "space" },
        on_press = function()
            self:toggle_window_search()
        end,
    })
    return actions
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
                app_switcher.update_hidden_states(self.hidden_states, event, application)
                if event == hs.application.watcher.unhidden then
                    self:handle_application_unhidden(application)
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

---@param settings Settings
---@param shortcuts ShortcutCenter|nil the center of the shortcuts of every utility, or nil for a
---center of this tool alone
---@return ProfileController
function profile_controller.start(settings, shortcuts)
    local preview_size = settings.preview_size
    if
        type(preview_size) ~= "table"
        or type(preview_size.w) ~= "number"
        or type(preview_size.h) ~= "number"
        or preview_size.w <= 0
        or preview_size.h <= 0
        or preview_size.w > 1
        or preview_size.h > 1
    then
        error(
            "the setting preview_size must give w and h as fractions of the screen,"
                .. " above 0 and at most 1",
            2
        )
    end
    if
        type(settings.list_font_size) ~= "number"
        or settings.list_font_size <= 0
        or settings.list_font_size > 0.1
    then
        error(
            string.format(
                "the setting list_font_size is %s, and it must be a fraction of the height of the"
                    .. " screen, above 0 and at most 0.1",
                tostring(settings.list_font_size)
            ),
            2
        )
    end
    if not title_overflow.is_valid(settings.title_overflow) then
        error(
            string.format(
                "the setting title_overflow is %q, which names no way",
                tostring(settings.title_overflow)
            ),
            2
        )
    end
    if math.type(settings.title_line_count) ~= "integer" or settings.title_line_count < 1 then
        error(
            string.format(
                "the setting title_line_count is %s, and it must be a whole number of 1 or more",
                tostring(settings.title_line_count)
            ),
            2
        )
    end
    if not list_sizing.is_valid(settings.list_sizing) then
        error(
            string.format(
                "the setting list_sizing is %q, which names no sizing",
                tostring(settings.list_sizing)
            ),
            2
        )
    end
    if not list_layout.is_valid(settings.list_layout) then
        error(
            string.format(
                "the setting list_layout is %q, which names no layout",
                tostring(settings.list_layout)
            ),
            2
        )
    end
    if type(settings.preview_blur) ~= "number" or settings.preview_blur < 1 then
        error(
            string.format(
                "the setting preview_blur is %s, and it must be a number of 1 or more",
                tostring(settings.preview_blur)
            ),
            2
        )
    end
    if not preview_method.is_valid(settings.preview_method) then
        error(
            string.format(
                "the setting preview_method is %q, which names no method",
                tostring(settings.preview_method)
            ),
            2
        )
    end
    local colors, colors_error = highlight_colors.complete(settings.search_highlight_colors)
    if not colors then
        error(colors_error, 2)
    end
    settings.search_highlight_colors = colors
    if not match_windows_by.is_valid(settings.match_windows_by) then
        error(
            string.format(
                "the setting match_windows_by is %q, which names no way to match windows",
                tostring(settings.match_windows_by)
            ),
            2
        )
    end
    if not missing_window_policy.is_valid(settings.missing_window_policy) then
        error(
            string.format(
                "the setting missing_window_policy is %q, which names no policy",
                tostring(settings.missing_window_policy)
            ),
            2
        )
    end
    if not hidden_application_windows.is_valid(settings.hidden_application_windows) then
        error(
            string.format(
                "the setting hidden_application_windows is %q, which names no choice",
                tostring(settings.hidden_application_windows)
            ),
            2
        )
    end
    if not concealment_method.is_valid(settings.concealment_method) then
        error(
            string.format(
                "the setting concealment_method is %q, which names no concealment method",
                tostring(settings.concealment_method)
            ),
            2
        )
    end
    local controller = setmetatable({
        settings = settings,
        log = hs.logger.new("desktop_mgr", "info"),
        watchers = {},
        is_busy = false,
        is_showing_desktop = false,
        work_number = 0,
        are_saves_suspended = false,
        window_ids_out_of_sight = {},
        are_snapshots_stopped = false,
        window_inventory = window_inventory.new(),
        reached_windows = {},
        hidden_states = {},
    }, ProfileController)
    local state, warning =
        state_file.read(settings.state_file_path, settings.initial_monitor_matching)
    controller.state = state
    if warning then
        controller.log.w(warning)
        notify(warning)
    end
    controller.screen_signature = read_screens.read_signature()
    controller.window_filter = track_windows.new_filter()
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
