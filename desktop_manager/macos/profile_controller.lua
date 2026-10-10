local arrangement_capture = require("desktop_manager.core.arrangement_capture")
local concealment_method = require("desktop_manager.core.concealment_method")
local conceal_windows = require("desktop_manager.macos.conceal_windows")
local launch_applications = require("desktop_manager.macos.launch_applications")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local profile_state = require("desktop_manager.core.profile_state")
local profile_switch = require("desktop_manager.core.profile_switch")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local restore_plan = require("desktop_manager.core.restore_plan")
local restore_windows = require("desktop_manager.macos.restore_windows")
local retained_timers = require("desktop_manager.macos.retained_timers")
local state_file = require("desktop_manager.macos.state_file")
local status_menu = require("desktop_manager.macos.status_menu")
local track_windows = require("desktop_manager.macos.track_windows")
local url_command = require("desktop_manager.core.url_command")
local window_matching = require("desktop_manager.core.window_matching")

local profile_controller = {}

local NOTIFICATION_TITLE = "Desktop Manager"
local STARTUP_PRUNE_DELAY_SECONDS = 5

---Owns the state, the hotkeys, the URL event, the menu bar item and the watchers.
---`is_busy` is true while a switch or a restore moves windows, and then no arrangement is saved.
---@class ProfileController
---@field settings Settings
---@field state State
---@field log table an hs.logger
---@field window_filter table an hs.window.filter
---@field menubar table an hs.menubar
---@field hotkeys table[]
---@field watchers table[]
---@field is_busy boolean
---@field are_saves_suspended boolean
---@field save_timer table|nil
---@field screen_timer table|nil
---@field screen_signature string the screens that the last arrangement was restored for
local ProfileController = {}
ProfileController.__index = ProfileController

---@param message string
local function notify(message)
    hs.notify.new({ title = NOTIFICATION_TITLE, informativeText = message }):send()
end

---@param window_ids integer[]
---@return table<integer, boolean>
local function to_set(window_ids)
    local set = {}
    for _, window_id in ipairs(window_ids) do
        set[window_id] = true
    end
    return set
end

---@param first string[]
---@param second string[]
---@return string[]
local function concatenate(first, second)
    local joined = { table.unpack(first) }
    for _, item in ipairs(second) do
        table.insert(joined, item)
    end
    return joined
end

---@param map table<integer, any>
---@return integer[] the keys of the map, in ascending order
local function list_keys(map)
    local keys = {}
    for key in pairs(map) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

---@param value any
---@return string
local function inspect_on_one_line(value)
    return hs.inspect(value, { newline = " ", indent = "" })
end

function ProfileController:write_state()
    if not state_file.write(self.settings.state_file_path, self.state) then
        self.log.e("the state could not be written to " .. self.settings.state_file_path)
    end
end

function ProfileController:refresh_menu()
    status_menu.show(self.menubar, self.state, self.settings.profile_count, {
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
    })
end

---@return MonitorConfiguration
function ProfileController:read_monitor_configuration()
    local screens = read_screens.describe_screens(self.settings.builtin_screen_name_patterns)
    return monitor_configuration.describe(screens, self.state.monitor_matching)
end

---@param windows table[] hs.window objects
---@return OwnedWindow[]
function ProfileController:describe_ownership(windows)
    local holders = profile_state.holders_by_window_id(self.state)
    local owned = {}
    for _, window in ipairs(windows) do
        local window_id = window:id()
        if window_id then
            table.insert(owned, {
                window_id = window_id,
                bundle_id = track_windows.bundle_id_of(window:application()),
                holder_numbers = holders[window_id] or {},
                is_minimized = window:isMinimized(),
            })
        end
    end
    return owned
end

---The windows of the window filter, and the windows of `window_ids` that the filter does not list.
---The filter drops a window whose subrole is not AXStandardWindow when the window hides or
---minimizes, as the window of Calendar does while Calendar is hidden.
---@param window_ids integer[]
---@return table[] hs.window objects
function ProfileController:list_known_windows(window_ids)
    local windows = self.window_filter:getWindows()
    local listed = track_windows.index_by_id(windows)
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

---@return integer[] the windows that some profile owns
function ProfileController:list_owned_window_ids()
    return list_keys(profile_state.holders_by_window_id(self.state))
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

---Saves where the windows of the active profile are, under the current monitor configuration.
---An owned window that the filter has not seen keeps its previous record with its current desktop.
---An owned window that is neither seen nor on any desktop is closed, and the profile forgets it.
function ProfileController:capture_active_arrangement()
    local number = self.state.active_profile_number
    if not number then
        return
    end
    local configuration = self:read_monitor_configuration()
    local previous = profile_state.find_arrangement(self.state, number, configuration.key)
    local previous_records = {}
    for _, record in ipairs(previous and previous.windows or {}) do
        if record.window_id then
            previous_records[record.window_id] = record
        end
    end
    local profile = profile_state.profile_or_default(self.state, number)
    local owned_ids = to_set(profile.window_ids)
    local observations, observed_ids = {}, {}
    for _, window in ipairs(self:list_known_windows(profile.window_ids)) do
        local window_id = window:id()
        if window_id and owned_ids[window_id] then
            table.insert(observations, track_windows.observe(window))
            observed_ids[window_id] = true
        end
    end
    local closed_ids = {}
    for _, window_id in ipairs(profile.window_ids) do
        if not observed_ids[window_id] then
            local space_id = read_desktops.find_window_space_id(window_id)
            local record = previous_records[window_id]
            if not space_id then
                table.insert(closed_ids, window_id)
            elseif record then
                table.insert(observations, {
                    window_id = window_id,
                    bundle_id = record.bundle_id,
                    app_name = record.app_name,
                    title = record.title,
                    space_id = space_id,
                    frame = nil,
                    is_minimized = false,
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
    self.state = profile_state.forget_windows(self.state, closed_ids)
    self.state = profile_state.with_arrangement(self.state, number, arrangement)
    self:write_state()
end

function ProfileController:schedule_save()
    if self.is_busy or self.are_saves_suspended or not self.state.active_profile_number then
        return
    end
    retained_timers.stop(self.save_timer)
    self.save_timer = retained_timers.after(self.settings.timing.save_delay_seconds, function()
        self.save_timer = nil
        if not self.is_busy and not self.are_saves_suspended then
            self:capture_active_arrangement()
        end
    end)
end

---@param failures string[]
function ProfileController:report_failures(failures)
    for _, failure in ipairs(failures) do
        self.log.w(failure)
    end
    if #failures > 0 then
        notify(string.format("%s (%d problems in the Hammerspoon console)", failures[1], #failures))
    end
end

---Restores the windows of the profile that are open, and returns the records that found no window.
---@param number integer
---@param arrangement Arrangement
---@param profile_left_number integer|nil the profile that was active before, whose windows that
---show on their saved desktop stay as they are
---@param on_done fun(failures: string[], unmatched_records: WindowRecord[])
function ProfileController:restore_open_windows(number, arrangement, profile_left_number, on_done)
    local profile = profile_state.profile_or_default(self.state, number)
    local live_windows, live_states = {}, {}
    for _, window in ipairs(self:list_known_windows(profile.window_ids)) do
        local window_id = window:id()
        if window_id and profile_state.holds_window(self.state, number, window_id) then
            local application = window:application()
            local bundle_id = track_windows.bundle_id_of(application)
            table.insert(
                live_windows,
                { window_id = window_id, bundle_id = bundle_id, title = window:title() or "" }
            )
            live_states[window_id] = {
                bundle_id = bundle_id,
                space_id = read_desktops.find_window_space_id(window_id),
                is_minimized = window:isMinimized(),
                is_app_hidden = application ~= nil and application:isHidden(),
                is_held_by_profile_left = profile_left_number ~= nil
                    and profile_state.holds_window(self.state, profile_left_number, window_id),
            }
        end
    end
    local match_result = window_matching.match_records_to_windows(arrangement.windows, live_windows)
    local plan = restore_plan.plan(
        arrangement,
        self:read_monitor_configuration(),
        read_desktops.read_desktop_layout(),
        match_result.matches,
        live_states
    )
    self.log.f(
        "restoring profile %d: %d of %d saved windows found, plan %s",
        number,
        #match_result.matches,
        #arrangement.windows,
        inspect_on_one_line(plan)
    )
    local context = {
        timing = self.settings.timing,
        find_window = function(window_id)
            return self:find_window(window_id)
        end,
        log_info = function(message)
            self.log.i(message)
        end,
    }
    restore_windows.apply(plan, context, function(failures)
        on_done(failures, match_result.unmatched_records)
    end)
end

---Launches the applications of the records that found no window, and places their new windows.
---A record whose application runs and whose window the profile still holds has a window that
---Hammerspoon cannot find, which is a failure unless the window sits on a desktop.
---A record whose window the profile no longer holds belongs to a window that was closed or left.
---@param number integer
---@param arrangement Arrangement
---@param unmatched_records WindowRecord[]
---@param on_done fun(failures: string[])
function ProfileController:restore_launched_windows(number, arrangement, unmatched_records, on_done)
    local bundle_ids, records_to_launch, is_listed, failures = {}, {}, {}, {}
    for _, record in ipairs(unmatched_records) do
        if hs.application.get(record.bundle_id) == nil then
            table.insert(records_to_launch, record)
            if not is_listed[record.bundle_id] then
                is_listed[record.bundle_id] = true
                table.insert(bundle_ids, record.bundle_id)
            end
        elseif
            record.window_id and profile_state.holds_window(self.state, number, record.window_id)
        then
            local space_id = read_desktops.find_window_space_id(record.window_id)
            if space_id then
                self.log.f(
                    "%s window %q stays on desktop %d, where Hammerspoon has not seen it yet",
                    record.app_name,
                    record.title,
                    space_id
                )
            else
                table.insert(
                    failures,
                    string.format(
                        "%s window %q of profile %d was not found",
                        record.app_name,
                        record.title,
                        number
                    )
                )
            end
        end
    end
    if #bundle_ids == 0 then
        on_done(failures)
        return
    end
    self.log.f("launching %s for profile %d", table.concat(bundle_ids, ", "), number)
    launch_applications.launch_and_wait(bundle_ids, self.settings.timing, function()
        local launched_arrangement = {
            monitor_configuration_key = arrangement.monitor_configuration_key,
            monitors = arrangement.monitors,
            focus = arrangement.focus,
            windows = records_to_launch,
        }
        self:restore_open_windows(number, launched_arrangement, nil, function(launch_failures)
            on_done(concatenate(failures, launch_failures))
        end)
    end)
end

---@param number integer
function ProfileController:activate_profile(number)
    if self.is_busy then
        hs.alert.show("Desktop Manager is still switching")
        return
    end
    if self.state.active_profile_number == number then
        return
    end
    local started_at = hs.timer.secondsSinceEpoch()
    local profile_left_number = self.state.active_profile_number
    self:capture_active_arrangement()
    self.is_busy = true
    retained_timers.stop(self.save_timer)
    local windows = self:list_known_windows(self:list_owned_window_ids())
    local unowned_ids = profile_switch.find_unowned_window_ids(self:describe_ownership(windows))
    self.state = profile_state.add_windows(self.state, number, unowned_ids)
    local concealment = profile_switch.plan_concealment(
        self.settings.concealment_method,
        self:describe_ownership(windows),
        number
    )
    self.log.f(
        "switching to profile %d: adopting %s, concealing %s",
        number,
        inspect_on_one_line(unowned_ids),
        inspect_on_one_line(concealment)
    )
    local failures = conceal_windows.apply(concealment, track_windows.index_by_id(windows))
    self.state = profile_state.with_active_profile_number(self.state, number)
    self:write_state()
    self:refresh_menu()
    hs.alert.show(profile_state.profile_or_default(self.state, number).name)
    local arrangement =
        profile_state.find_arrangement(self.state, number, self:read_monitor_configuration().key)
    local function finish(more_failures)
        local all_failures = concatenate(failures, more_failures)
        self.is_busy = false
        self.log.f(
            "profile %d is active after %.1f seconds, with %d problems",
            number,
            hs.timer.secondsSinceEpoch() - started_at,
            #all_failures
        )
        self:report_failures(all_failures)
    end
    if not arrangement then
        finish({})
        return
    end
    retained_timers.after(self.settings.timing.window_settle_seconds, function()
        self:restore_open_windows(
            number,
            arrangement,
            profile_left_number,
            function(open_failures, unmatched_records)
                self:restore_launched_windows(
                    number,
                    arrangement,
                    unmatched_records,
                    function(launch_failures)
                        finish(concatenate(open_failures, launch_failures))
                    end
                )
            end
        )
    end)
end

function ProfileController:deactivate_profile()
    if self.is_busy or not self.state.active_profile_number then
        return
    end
    self:capture_active_arrangement()
    self.state = profile_state.with_active_profile_number(self.state, nil)
    self:write_state()
    self:refresh_menu()
    hs.alert.show("No desktop profile")
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

---@param matching string
function ProfileController:set_monitor_matching(matching)
    self:capture_active_arrangement()
    self.state = profile_state.with_monitor_matching(self.state, matching)
    self:write_state()
    self:refresh_menu()
    hs.alert.show("Same monitor configuration by " .. monitor_matching.label_of(matching):lower())
end

---@param params table<string, string>
function ProfileController:run_url_command(params)
    local command, error_message = url_command.parse(params, self.settings.profile_count)
    if not command then
        notify(error_message)
        return
    end
    if command.action == url_command.ACTIVATE then
        self:activate_profile(command.profile_number)
    elseif command.action == url_command.TOGGLE then
        self:toggle_profile(command.profile_number)
    elseif command.action == url_command.DEACTIVATE then
        self:deactivate_profile()
    elseif command.action == url_command.RENAME then
        self:rename_profile(command.profile_number, command.name)
    elseif command.action == url_command.CYCLE_MONITOR_MATCHING then
        self:set_monitor_matching(monitor_matching.next_after(self.state.monitor_matching))
    elseif command.action == url_command.SAVE then
        self:capture_active_arrangement()
    end
end

---@param window table an hs.window
function ProfileController:handle_window_created(window)
    local window_id = window:id()
    local number = self.state.active_profile_number
    if
        window_id
        and number
        and profile_state.holders_by_window_id(self.state)[window_id] == nil
    then
        self.state = profile_state.add_windows(self.state, number, { window_id })
        self:write_state()
    end
    self:schedule_save()
end

---@param window table an hs.window
function ProfileController:handle_window_destroyed(window)
    local window_id = window:id()
    if window_id and profile_state.holders_by_window_id(self.state)[window_id] then
        self.state = profile_state.forget_windows(self.state, { window_id })
        self:write_state()
    end
    self:schedule_save()
end

---A window that the user unminimizes joins the active profile, and stays in its other profiles.
---@param window table an hs.window
function ProfileController:handle_window_unminimized(window)
    local window_id = window:id()
    local number = self.state.active_profile_number
    if
        not self.is_busy
        and window_id
        and number
        and not profile_state.holds_window(self.state, number, window_id)
    then
        self.state = profile_state.add_windows(self.state, number, { window_id })
        self:write_state()
    end
    self:schedule_save()
end

---A window that the user minimizes leaves the active profile when another profile holds it too.
---A window that only the active profile holds stays there, saved as minimized.
---@param window table an hs.window
function ProfileController:handle_window_minimized(window)
    local window_id = window:id()
    local number = self.state.active_profile_number
    local holders = window_id and profile_state.holders_by_window_id(self.state)[window_id] or {}
    if
        not self.is_busy
        and number
        and #holders > 1
        and profile_state.holds_window(self.state, number, window_id)
    then
        self.state = profile_state.remove_windows(self.state, number, { window_id })
        self:write_state()
    end
    self:schedule_save()
end

---Unhiding an application shows all its windows.
---After an unhide that a restore makes, the windows that the active profile does not hold are
---minimized again.
---After an unhide that the user makes, those windows stay in sight and join the active profile.
---@param application table an hs.application
function ProfileController:handle_application_unhidden(application)
    local number = self.state.active_profile_number
    if not number or not application then
        return
    end
    local holders = profile_state.holders_by_window_id(self.state)
    local joining_ids = {}
    for _, window in ipairs(application:allWindows()) do
        local window_id = window:id()
        local is_held_elsewhere_alone = window_id ~= nil
            and holders[window_id] ~= nil
            and not profile_state.holds_window(self.state, number, window_id)
        if is_held_elsewhere_alone and not window:isMinimized() then
            if self.is_busy then
                window:minimize()
            else
                table.insert(joining_ids, window_id)
            end
        end
    end
    if #joining_ids > 0 then
        self.state = profile_state.add_windows(self.state, number, joining_ids)
        self:write_state()
    end
end

---macOS reports a change of the screen parameters also when the Dock changes size, and such a
---change leaves the signature of the screens as it was.
function ProfileController:handle_screens_changed()
    if self.screen_timer == nil and read_screens.read_signature() == self.screen_signature then
        return
    end
    self.are_saves_suspended = true
    retained_timers.stop(self.save_timer)
    retained_timers.stop(self.screen_timer)
    self.screen_timer = retained_timers.after(self.settings.timing.screen_settle_seconds, function()
        self.screen_timer = nil
        self.screen_signature = read_screens.read_signature()
        local number = self.state.active_profile_number
        local configuration = self:read_monitor_configuration()
        local arrangement = number
            and profile_state.find_arrangement(self.state, number, configuration.key)
        if not arrangement or self.is_busy then
            self.are_saves_suspended = false
            self:schedule_save()
            return
        end
        self.is_busy = true
        hs.alert.show("Restoring " .. configuration.key)
        self:restore_open_windows(number, arrangement, nil, function(failures)
            self.is_busy = false
            self.are_saves_suspended = false
            self:report_failures(failures)
        end)
    end)
end

---Forgets the owned windows that closed while Hammerspoon was not running.
function ProfileController:forget_closed_windows()
    local known_windows = self:list_known_windows(self:list_owned_window_ids())
    local seen_ids = track_windows.index_by_id(known_windows)
    local closed_ids = {}
    for window_id in pairs(profile_state.holders_by_window_id(self.state)) do
        if not seen_ids[window_id] and not read_desktops.find_window_space_id(window_id) then
            table.insert(closed_ids, window_id)
        end
    end
    if #closed_ids > 0 then
        self.state = profile_state.forget_windows(self.state, closed_ids)
        self:write_state()
    end
end

---Prints what the tool reads of the screens, desktops and windows, without changing anything.
function ProfileController:print_diagnostics()
    local lines = {}
    local function add(format, ...)
        table.insert(lines, string.format(format, ...))
    end
    add("accessibility permission: %s", tostring(hs.accessibilityState()))
    add("running timers: %d", retained_timers.count_running())
    add("monitor matching: %s", self.state.monitor_matching)
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
        local numbered = {}
        for _, space_id in ipairs(screen.space_ids) do
            table.insert(
                numbered,
                string.format(
                    "%d(Control-%s)",
                    space_id,
                    tostring(read_desktops.find_desktop_shortcut_number(space_id))
                )
            )
        end
        add(
            "  desktops of %s: %s, active %s",
            screen.screen_uuid,
            table.concat(numbered, " "),
            tostring(screen.active_space_id)
        )
    end
    add("focused desktop: %s", tostring(layout.focused_space_id))
    add("active profile: %s", tostring(self.state.active_profile_number))
    local holders = profile_state.holders_by_window_id(self.state)
    local listed = track_windows.index_by_id(self.window_filter:getWindows())
    for _, window in ipairs(self:list_known_windows(self:list_owned_window_ids())) do
        local observation = track_windows.observe(window)
        local application = window:application()
        add(
            "  window %s %s %q desktop=%s minimized=%s hidden=%s in-filter=%s profiles=%s",
            tostring(observation.window_id),
            observation.bundle_id,
            observation.title,
            tostring(observation.space_id),
            tostring(observation.is_minimized),
            tostring(application ~= nil and application:isHidden()),
            tostring(listed[observation.window_id] ~= nil),
            table.concat(holders[observation.window_id] or {}, ",")
        )
    end
    print(table.concat(lines, "\n"))
end

function ProfileController:bind_hotkeys()
    local modifiers = self.settings.hotkey_modifiers
    for number = 1, self.settings.profile_count do
        table.insert(
            self.hotkeys,
            hs.hotkey.bind(modifiers, tostring(number), function()
                self:toggle_profile(number)
            end)
        )
    end
    table.insert(
        self.hotkeys,
        hs.hotkey.bind(modifiers, "0", function()
            self:deactivate_profile()
        end)
    )
end

function ProfileController:start_watchers()
    local filter = hs.window.filter
    self.window_filter:subscribe({
        [filter.windowCreated] = function(window)
            self:handle_window_created(window)
        end,
        [filter.windowDestroyed] = function(window)
            self:handle_window_destroyed(window)
        end,
        [filter.windowMoved] = function()
            self:schedule_save()
        end,
        [filter.windowMinimized] = function(window)
            self:handle_window_minimized(window)
        end,
        [filter.windowUnminimized] = function(window)
            self:handle_window_unminimized(window)
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
            end)
            :start()
    )
    table.insert(
        self.watchers,
        hs.application.watcher
            .new(function(_, event, application)
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
        end)
    )
end

---@param settings Settings
---@return ProfileController
function profile_controller.start(settings)
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
        hotkeys = {},
        watchers = {},
        is_busy = false,
        are_saves_suspended = false,
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
    controller:bind_hotkeys()
    hs.urlevent.bind(settings.url_event_name, function(_, params)
        controller:run_url_command(params)
    end)
    controller:start_watchers()
    retained_timers.after(STARTUP_PRUNE_DELAY_SECONDS, function()
        controller:forget_closed_windows()
    end)
    if not hs.accessibilityState() then
        notify("Hammerspoon needs the Accessibility permission to move windows")
    end
    return controller
end

return profile_controller
