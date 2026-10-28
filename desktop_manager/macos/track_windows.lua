local concatenate_lists = require("desktop_manager.core.concatenate_lists")
local poll_until = require("desktop_manager.macos.poll_until")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")

local track_windows = {}

---Each poll for the windows that accessibility does not reach yet, or for a standard window of an
---application after its unhide, asks the applications for their windows through accessibility,
---which takes a while with many windows.
local REACH_POLL_SECONDS = 0.2

---The kind of an hs.application with a Dock icon.
track_windows.REGULAR_APPLICATION_KIND = 1

---What `bundle_id_of` gives for an application without a bundle id and a name.
track_windows.UNKNOWN_BUNDLE_ID = "unknown"

---@param application table an hs.application
---@param named_bundle_ids table<string, boolean>
---@return boolean whether the desktop manager follows the windows of the application: it has a
---Dock icon, or the profiles name it
function track_windows.is_followed(application, named_bundle_ids)
    return application:kind() == track_windows.REGULAR_APPLICATION_KIND
        or named_bundle_ids[track_windows.bundle_id_of(application)] == true
end

---Leaves the applications that the desktop manager does not follow out of every window filter.
---The window filter asks each application that it follows for its windows at each change of
---desktop, and reacts to its accessibility notifications.
---During the switches of 2026-10-28 on macOS 27, applications without a Dock icon, such as
---MenuBarAgent, BetterDisplay, Siri and GlobalProtect, took up to 1.5 seconds for one answer, and
---the answers together blocked Hammerspoon for up to 5 seconds at a time.
---The window filter reads `hs.window.filter.ignoreAlways` by the name of an application before it
---follows the application: at its own start, at each launch, and at each activation of an
---application that it does not follow yet, so an index function there decides at each read.
---An application that gains a Dock icon is therefore followed from its next activation on.
---An application that the filter follows stays followed until it quits, because the filter keeps
---following it, and leaving it out then would only reject its windows with a warning each time.
---@param named_bundle_ids table<string, boolean>
local function follow_only_dock_applications(named_bundle_ids)
    ---@type table<string, table> an hs.application of each name that the filter follows
    local followed_by_name = {}
    setmetatable(hs.window.filter.ignoreAlways, {
        __index = function(_, app_name)
            local followed = followed_by_name[app_name]
            if followed and followed:isRunning() then
                return false
            end
            followed_by_name[app_name] = nil
            local is_running = false
            for _, application in ipairs(hs.application.runningApplications()) do
                if application:name() == app_name then
                    if track_windows.is_followed(application, named_bundle_ids) then
                        followed_by_name[app_name] = application
                        return false
                    end
                    is_running = true
                end
            end
            return is_running
        end,
    })
end

---A window filter that sees the standard windows of every desktop, of the applications that the
---desktop manager follows, as `track_windows.is_followed` says.
---Minimized windows and the windows of hidden applications count as well.
---@param named_bundle_ids table<string, boolean> the applications that the profiles name, which
---the filter follows also without a Dock icon
---@return table filter an hs.window.filter
function track_windows.new_filter(named_bundle_ids)
    follow_only_dock_applications(named_bundle_ids)
    -- `hs.window.filter.forceRefreshOnSpaceChange` keeps its default, false, so that a version of
    -- Hammerspoon that honours it asks no application for its windows at a change of desktop.
    -- The windows that the filter has not seen yet reach the desktop manager through the list of
    -- the window server, as `window_inventory` says.
    -- The installed `window_filter.lua` asks the applications that it follows at each change that
    -- `hs.spaces.watcher` reports, whatever the field says.
    return hs.window.filter.new():setDefaultFilter({ allowRoles = "AXStandardWindow" })
end

---@return table[] the hs.window objects of every application that the window filter follows, as
---`hs.window.allWindows` gives them for every application with a Dock icon or without one
function track_windows.list_followed_windows()
    local windows = {}
    for _, application in ipairs(hs.application.runningApplications()) do
        if
            application:kind() >= 0 and not hs.window.filter.ignoreAlways[application:name() or ""]
        then
            windows = concatenate_lists.concatenate(windows, application:allWindows())
        end
    end
    return windows
end

---@param application table|nil an hs.application
---@return string
function track_windows.bundle_id_of(application)
    if not application then
        return track_windows.UNKNOWN_BUNDLE_ID
    end
    return application:bundleID() or application:name() or track_windows.UNKNOWN_BUNDLE_ID
end

---@param application table|nil an hs.application
---@return string bundle_id the bundle id of the application, as `bundle_id_of` gives it
---@return string app_name the name of the application, or "unknown"
function track_windows.identify_application(application)
    return track_windows.bundle_id_of(application), application and application:name() or "unknown"
end

---The running application of the bundle id, found without the search of `hs.application.get`
---through every window of every application when no application of the bundle id runs.
---@param bundle_id string
---@return table|nil an hs.application
function track_windows.find_running_application(bundle_id)
    return hs.application.applicationsForBundleID(bundle_id)[1]
end

---Every running application of each bundle id, in the order of the bundle ids, also a second
---instance of an application.
---@param bundle_ids string[]
---@return table[] hs.application objects
function track_windows.list_running_applications(bundle_ids)
    local applications = {}
    for _, bundle_id in ipairs(bundle_ids) do
        for _, application in ipairs(hs.application.applicationsForBundleID(bundle_id)) do
            table.insert(applications, application)
        end
    end
    return applications
end

---@param windows table[] hs.window objects
---@return table<integer, table> the hs.window of each window id
function track_windows.index_by_id(windows)
    local index = {}
    for _, window in ipairs(windows) do
        local window_id = window:id()
        if window_id then
            index[window_id] = window
        end
    end
    return index
end

---@param windows table[] hs.window objects
---@return table<integer, boolean> the ids of the windows
function track_windows.index_ids(windows)
    local ids = {}
    for _, window in ipairs(windows) do
        local window_id = window:id()
        if window_id then
            ids[window_id] = true
        end
    end
    return ids
end

---@param window table an hs.window
---@return string such as 'Safari window "Inbox"', or 'a window "Inbox"' when Hammerspoon gives the
---window no application
function track_windows.describe(window)
    local application = window:application()
    return string.format(
        "%s window %q",
        application and application:name() or "a",
        window:title() or ""
    )
end

---Reads the application of the window, its bundle id, whether the window is minimized and whether
---the application is hidden, in that order.
---@param window table an hs.window
---@return WindowState
function track_windows.read_window_state(window)
    local application = window:application()
    return {
        bundle_id = track_windows.bundle_id_of(application),
        is_minimized = window:isMinimized(),
        is_app_hidden = application ~= nil and application:isHidden(),
    }
end

---@param window table an hs.window
---@return WindowObservation
function track_windows.observe(window)
    local application = window:application()
    local window_id = window:id()
    local is_minimized = window:isMinimized()
    local is_app_hidden = application ~= nil and application:isHidden()
    local bundle_id, app_name = track_windows.identify_application(application)
    return {
        window_id = window_id,
        bundle_id = bundle_id,
        app_name = app_name,
        title = window:title() or "",
        space_id = not is_minimized and read_desktops.find_window_space_id(window_id) or nil,
        frame = not is_minimized and read_screens.to_rect(window:frame()) or nil,
        is_out_of_sight = is_minimized or is_app_hidden,
    }
end

---@param windows ServerWindow[]
---@return table<integer, table> the hs.window of each window of the owning applications that
---accessibility reaches now
local function find_reached_windows(windows)
    local bundle_ids, owned_windows = {}, {}
    for _, window in ipairs(windows) do
        bundle_ids[window.bundle_id] = true
    end
    for bundle_id in pairs(bundle_ids) do
        for _, application in ipairs(hs.application.applicationsForBundleID(bundle_id)) do
            owned_windows = concatenate_lists.concatenate(owned_windows, application:allWindows())
        end
    end
    return track_windows.index_by_id(owned_windows)
end

---Waits until accessibility reaches every one of the windows that Hammerspoon had not seen, as
---after a move into view or a press in Mission Control, up to the time limit.
---Each poll reads the windows of the owning applications once, instead of every window of every
---application as `hs.window.get` does.
---@param windows ServerWindow[]
---@param timeout_seconds number
---@param on_done fun(reached: table<integer, table>) the hs.window of each window that
---accessibility reaches, by its id
function track_windows.wait_until_reached(windows, timeout_seconds, on_done)
    local reached = {}
    poll_until.wait(
        function()
            reached = find_reached_windows(windows)
            for _, window in ipairs(windows) do
                if not reached[window.window_id] then
                    return false
                end
            end
            return true
        end,
        timeout_seconds,
        REACH_POLL_SECONDS,
        function()
            local found = {}
            for _, window in ipairs(windows) do
                found[window.window_id] = reached[window.window_id]
            end
            on_done(found)
        end
    )
end

---@param application table an hs.application
---@return table|nil the main window of the application when it is a standard window, and otherwise
---its first standard window
local function find_standard_window(application)
    local main_window = application:mainWindow()
    if main_window and main_window:isStandard() then
        return main_window
    end
    for _, window in ipairs(application:allWindows()) do
        if window:isStandard() then
            return window
        end
    end
    return nil
end

---Waits until the application shows a standard window, as after an unhide, while its windows may
---still report another subrole such as `AXDialog`, up to the time limit.
---@param application table an hs.application
---@param timeout_seconds number
---@param on_done fun(window: table|nil) the main window of the application when it is a standard
---window, and otherwise its first standard window, or nil after the time limit
function track_windows.wait_until_standard(application, timeout_seconds, on_done)
    poll_until.wait_for_value(function()
        return find_standard_window(application)
    end, timeout_seconds, REACH_POLL_SECONDS, on_done)
end

---Waits until the window is a standard window, as after the unhide of its application, up to the
---time limit.
---@param window table an hs.window
---@param timeout_seconds number
---@param on_done fun(window: table|nil) the window, or nil after the time limit
function track_windows.wait_until_window_standard(window, timeout_seconds, on_done)
    poll_until.wait_for_value(function()
        return window:isStandard() and window or nil
    end, timeout_seconds, REACH_POLL_SECONDS, on_done)
end

return track_windows
