local app_numbers = require("desktop_manager.core.app_numbers")
local app_switcher = require("desktop_manager.macos.app_switcher")
local arrangement_capture = require("desktop_manager.core.arrangement_capture")
local concealment_method = require("desktop_manager.core.concealment_method")
local conceal_windows = require("desktop_manager.macos.conceal_windows")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local missing_windows = require("desktop_manager.core.missing_windows")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local new_windows = require("desktop_manager.macos.new_windows")
local place_windows = require("desktop_manager.macos.place_windows")
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
---@field window_ids_out_of_sight table<integer, boolean> the windows that the last switch took out
---of sight
local ProfileController = {}
ProfileController.__index = ProfileController

---@param message string
local function notify(message)
    hs.notify.new({ title = NOTIFICATION_TITLE, informativeText = message }):send()
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

---The windows of the window filter, and the windows of `window_ids` that the filter does not list.
---The filter drops a window whose subrole is not AXStandardWindow when the window hides or
---minimizes, as the window of Calendar does while Calendar is hidden.
---@param window_ids integer[]
---@return table[] hs.window objects
function ProfileController:list_known_windows(window_ids)
    local windows = {}
    for _, window in ipairs(self.window_filter:getWindows()) do
        if has_valid_id(window) then
            table.insert(windows, window)
        end
    end
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

---Records every window that the tool sees, under the current monitor configuration.
---A recorded window that the tool does not see but that sits on a desktop keeps its previous record
---with its current desktop, because Hammerspoon sees the windows of a desktop once it was visited.
function ProfileController:capture_active_arrangement()
    local number = self.state.active_profile_number
    if not number then
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
    local observations, observed_ids = {}, {}
    for _, window in ipairs(known_windows) do
        local observation = track_windows.observe(window)
        if observation.window_id then
            table.insert(observations, observation)
            observed_ids[observation.window_id] = true
        end
    end
    for _, record in ipairs(previous and previous.windows or {}) do
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

---Brings the matched windows to the desktops and frames that the arrangement records.
---@param number integer
---@param arrangement Arrangement
---@param matches WindowMatch[]
---@param window_by_id table<integer, table> the hs.window of each matched window id
---@param on_done fun(failures: string[])
function ProfileController:restore_matched_windows(
    number,
    arrangement,
    matches,
    window_by_id,
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
                space_id = read_desktops.find_window_space_id(match.window_id),
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
        log_info = function(message)
            self.log.i(message)
        end,
    }
    restore_windows.apply(plan, context, on_done)
end

---Restores the open windows of an arrangement, and returns the records that found no window.
---@param number integer
---@param arrangement Arrangement
---@param on_done fun(failures: string[], unmatched_records: WindowRecord[])
function ProfileController:restore_open_windows(number, arrangement, on_done)
    local windows = self:list_known_windows(list_recorded_window_ids(arrangement))
    local _, live_windows = describe_open_windows(windows)
    local match_result = window_matching.match_records_to_open_windows(
        self.settings.missing_window_policy,
        arrangement.windows,
        live_windows
    )
    self:restore_matched_windows(
        number,
        arrangement,
        match_result.matches,
        track_windows.index_by_id(windows),
        function(failures)
            on_done(failures, match_result.unmatched_records)
        end
    )
end

---Gives each record in sight whose window no longer exists a new window of its application, on its
---recorded desktop and with its recorded frame, and writes the new window ids into the records of
---every profile.
---A record whose window sits on a desktop that Hammerspoon has not seen keeps that window.
---@param number integer
---@param unmatched_records WindowRecord[]
---@param on_done fun(failures: string[])
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
                "%s window %q stays on desktop %d, where Hammerspoon has not seen it yet",
                record.app_name,
                record.title,
                space_id
            )
        else
            table.insert(missing_records, record)
        end
    end
    local plan = missing_windows.plan_visits(
        missing_records,
        self:read_monitor_configuration(),
        read_desktops.read_desktop_layout()
    )
    for _, record in ipairs(plan.unplaced_records) do
        self.log.f("%s window %q has no recorded desktop here", record.app_name, record.title)
    end
    local session = new_windows.start_session(self.settings.timing)
    local failures, renames = {}, {}
    local visit_index, window_index = 1, 0
    local next_window
    local function finish()
        if #renames > 0 then
            self.state = profile_state.rename_windows(self.state, renames)
            self:write_state()
        end
        on_done(failures)
    end
    local function open_on_visit(visit)
        window_index = window_index + 1
        local missing_window = visit.missing_windows[window_index]
        if not missing_window then
            visit_index, window_index = visit_index + 1, 0
            next_window()
            return
        end
        local record = missing_window.record
        session:provide_window(record, function(window, error_message)
            if not window then
                table.insert(failures, error_message)
            else
                place_windows.fit_frame(window, missing_window.placement)
                self.log.f(
                    "profile %d: %s window %q is now window %d",
                    number,
                    record.app_name,
                    record.title,
                    window:id()
                )
                if record.window_id then
                    table.insert(renames, {
                        bundle_id = record.bundle_id,
                        old_window_id = record.window_id,
                        new_window_id = window:id(),
                    })
                end
            end
            open_on_visit(visit)
        end)
    end
    next_window = function()
        local visit = plan.visits[visit_index]
        if not visit then
            finish()
            return
        end
        if window_index > 0 then
            open_on_visit(visit)
            return
        end
        place_windows.show_desktop(
            visit.screen_uuid,
            visit.desktop_number,
            self.settings.timing,
            function(_, error_message)
                if error_message then
                    table.insert(failures, error_message)
                    visit_index = visit_index + 1
                    next_window()
                    return
                end
                open_on_visit(visit)
            end
        )
    end
    next_window()
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
    self:capture_active_arrangement()
    self.is_busy = true
    retained_timers.stop(self.save_timer)
    local configuration_key = self:read_monitor_configuration().key
    local windows = self:list_known_windows(
        list_recorded_window_ids(
            profile_state.find_arrangement(self.state, number, configuration_key)
        )
    )
    self:rename_reopened_windows(windows)
    local saved_arrangement = profile_state.find_arrangement(self.state, number, configuration_key)
    local arrangement = saved_arrangement
        or { monitor_configuration_key = configuration_key, monitors = {}, windows = {} }
    local open_windows, live_windows = describe_open_windows(windows)
    local match_result = window_matching.match_records_to_open_windows(
        self.settings.missing_window_policy,
        arrangement.windows,
        live_windows
    )
    local candidates = profile_switch.mark_kept_windows(
        open_windows,
        match_result.matches,
        profile_state.index_recorded_windows(self.state)
    )
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
    local failures = conceal_windows.apply(concealment, window_by_id)
    self.state = profile_state.with_active_profile_number(self.state, number)
    self:write_state()
    self:refresh_menu()
    hs.alert.show(profile_state.profile_or_default(self.state, number).name)
    local function finish(more_failures)
        local all_failures = concatenate(failures, more_failures)
        self.is_busy = false
        self:schedule_save()
        self.log.f(
            "profile %d is active after %.1f seconds, with %d problems",
            number,
            hs.timer.secondsSinceEpoch() - started_at,
            #all_failures
        )
        self:report_failures(all_failures)
    end
    if not saved_arrangement then
        finish({})
        return
    end
    retained_timers.after(self.settings.timing.window_settle_seconds, function()
        self:open_missing_windows(number, match_result.unmatched_records, function(opening_failures)
            self:restore_matched_windows(
                number,
                arrangement,
                match_result.matches,
                window_by_id,
                function(restore_failures)
                    finish(concatenate(opening_failures, restore_failures))
                end
            )
        end)
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

---@param matching string
function ProfileController:set_monitor_matching(matching)
    self:capture_active_arrangement()
    self.state = profile_state.with_monitor_matching(self.state, matching)
    self:write_state()
    self:refresh_menu()
    hs.alert.show("Same monitor configuration by " .. monitor_matching.label_of(matching):lower())
end

---Gives the number to the application in the active profile, as the user chose.
---@param app_number integer
---@param bundle_id string
---@param app_name string
function ProfileController:choose_app_number(app_number, bundle_id, app_name)
    local number = self.state.active_profile_number
    if not number then
        notify("No profile is active, so no application can get a number")
        return
    end
    local profile = profile_state.profile_or_default(self.state, number)
    self.state = profile_state.with_app_numbers(
        self.state,
        number,
        app_numbers.choose(profile.app_numbers, app_number, bundle_id, app_name)
    )
    self:write_state()
    hs.alert.show(string.format("%s is number %d in %s", app_name, app_number, profile.name))
end

---Returns the number to the defaults of the active profile, which the next update gives again.
---@param app_number integer
function ProfileController:release_app_number(app_number)
    local number = self.state.active_profile_number
    if not number then
        return
    end
    local profile = profile_state.profile_or_default(self.state, number)
    self.state = profile_state.with_app_numbers(
        self.state,
        number,
        app_numbers.release(profile.app_numbers, app_number)
    )
    self:capture_active_arrangement()
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

---Brings a window of the application of the number to the front, or passes the keys through to
---the application in front when the active profile gives the number to no application.
---@param app_number integer
---@param hotkey table the hs.hotkey of the number
function ProfileController:press_app_number(app_number, hotkey)
    local number = self.state.active_profile_number
    local entry = number
        and app_numbers.find_by_number(
            profile_state.profile_or_default(self.state, number).app_numbers,
            app_number
        )
    if not entry then
        hotkey:disable()
        hs.eventtap.keyStroke(self.settings.app_hotkey_modifiers, tostring(app_number), 0)
        hotkey:enable()
        return
    end
    app_switcher.switch_to_application(
        entry,
        self.window_filter:getWindows(),
        self:list_recorded_window_ids_of_application(entry.bundle_id),
        self.settings.timing,
        function(error_message)
            if error_message then
                self:report_failures({ error_message })
            end
        end
    )
end

function ProfileController:bind_app_hotkeys()
    for app_number = 1, self.settings.app_number_count do
        local hotkey
        hotkey = hs.hotkey.bind(self.settings.app_hotkey_modifiers, tostring(app_number), function()
            self:press_app_number(app_number, hotkey)
        end)
        table.insert(self.hotkeys, hotkey)
    end
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
    elseif command.action == url_command.SAVE then
        self:capture_active_arrangement()
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
        self:restore_open_windows(number, arrangement, function(failures)
            self.is_busy = false
            self.are_saves_suspended = false
            self:report_failures(failures)
        end)
    end)
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
    if self.state.active_profile_number then
        local profile =
            profile_state.profile_or_default(self.state, self.state.active_profile_number)
        for _, entry in ipairs(profile.app_numbers) do
            add(
                "  app number %d: %s %s%s",
                entry.number,
                entry.app_name,
                entry.bundle_id,
                entry.is_chosen_by_user and " (chosen)" or ""
            )
        end
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
    if not missing_window_policy.is_valid(settings.missing_window_policy) then
        error(
            string.format(
                "the setting missing_window_policy is %q, which names no policy",
                tostring(settings.missing_window_policy)
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
        hotkeys = {},
        watchers = {},
        is_busy = false,
        are_saves_suspended = false,
        window_ids_out_of_sight = {},
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
    controller:bind_app_hotkeys()
    hs.urlevent.bind(settings.url_event_name, function(_, params)
        controller:run_url_command(params)
    end)
    controller:start_watchers()
    if not hs.accessibilityState() then
        notify("Hammerspoon needs the Accessibility permission to move windows")
    end
    return controller
end

return profile_controller
