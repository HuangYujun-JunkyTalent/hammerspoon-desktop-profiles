local concealment_method = require("desktop_manager.core.concealment_method")
local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")
local list_layout = require("desktop_manager.core.list_layout")
local list_sizing = require("desktop_manager.core.list_sizing")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local preview_method = require("desktop_manager.core.preview_method")
local title_overflow = require("desktop_manager.core.title_overflow")
local unmatched_window_action = require("desktop_manager.core.unmatched_window_action")

local default_settings = {}

---@class Timing
---@field poll_interval_seconds number the time between two reads of a condition that a wait
---polls, such as the release of the modifier keys, the arrival of a moved window or the desktop
---that a press shows
---@field modifier_release_timeout_seconds number the longest wait for the release of the modifier
---keys before Mission Control opens, after which Mission Control stays closed and the alert after
---the switch says so
---@field desktop_show_timeout_seconds number the wait after the last press on the thumbnail of a
---desktop in Mission Control, the first press or the press of the second opening, until its screen
---reports the desktop and Mission Control has closed
---@field desktop_press_retry_seconds number the time after the first press on a thumbnail at which
---the thumbnail is pressed a second time when the desktop is not active and Mission Control shows,
---or Mission Control opens a second time when it has closed
---@field desktop_settle_seconds number the wait after a press has shown its desktop and Mission
---Control has closed, before the next step
---@field minimize_timeout_seconds number the longest wait until the windows that a restore
---unminimizes are no longer minimized
---@field window_settle_seconds number the wait for the windows to settle after the desktop manager
---unhides applications, unminimizes windows, sets frames or conceals the windows of a switch, and
---after a new window opens
---@field window_move_timeout_seconds number the wait for each window that moves by its id to
---another desktop of its screen
---@field window_reach_timeout_seconds number the wait until accessibility reaches a window that
---Hammerspoon had not seen, after its move into view or after a press of the list or the search
---showed its desktop
---@field busy_watchdog_seconds number the longest switch, restore, or press of the list or the
---search, after which the desktop manager stops it and reports a failure
---@field mission_control_timeout_seconds number the longest wait for Mission Control to show the
---group of the display after it opens
---@field mission_control_press_gap_seconds number the wait after Mission Control shows or closes,
---and after each addition or removal of a desktop, before the next step
---@field application_launch_timeout_seconds number the longest wait for the new window of an
---application, after which a notification reports the application
---@field application_focus_timeout_seconds number the wait after the focus before a press of the
---list or the search until the application of the chosen window is the frontmost application
---@field save_delay_seconds number the wait from a request of an update of the records and the
---numbers until the update, such as after a window opens, closes, moves, minimizes or changes its
---title, after a change of desktop, after a switch or a restore, and at each tick of
---periodic_save_seconds, and a request within the wait starts the wait again
---@field periodic_save_seconds number the time between two updates of the record of the active
---profile and two readings of the list of all windows of macOS that no event starts
---@field screen_settle_seconds number the wait after a change of the monitors for macOS to move
---the windows, before the restore of the active profile
---@field snapshot_time_limit_seconds number a slower capture of a preview stops the previews until
---a reload

---@class Settings
---@field state_file_path string
---@field profile_count integer
---@field app_number_count integer
---@field url_event_name string
---@field initial_monitor_matching string
---@field concealment_method ConcealmentMethod
---@field match_windows_by MatchWindowsBy
---@field missing_window_policy MissingWindowPolicy
---@field unmatched_window_action UnmatchedWindowAction
---@field hidden_application_windows HiddenApplicationWindows
---@field search_highlight_colors table|nil the colors of highlight_colors that replace the
---defaults, by name, such as `{ selection = { hex = "#2E8B57", alpha = 0.9 } }`
---@field preview_method PreviewMethod
---@field preview_blur number 1 or more: a preview keeps 1 / preview_blur of the detail of its size
---@field preview_size table the w and h of a preview, as fractions of the width and height of the
---screen in front
---@field list_font_size number the size of the titles, as a fraction of the height of the screen
---in front
---@field list_layout ListLayout
---@field list_sizing ListSizing
---@field title_overflow TitleOverflow
---@field title_line_count integer the most lines of a title under title_overflow wrap
---@field builtin_screen_name_patterns string[]
---@field timing Timing

---@param state_file_path string
---@return Settings
function default_settings.create(state_file_path)
    return {
        state_file_path = state_file_path,
        profile_count = 9,
        app_number_count = 9,
        url_event_name = "desktop-manager",
        initial_monitor_matching = monitor_matching.BY_COUNT,
        concealment_method = concealment_method.MINIMIZE_WINDOWS,
        match_windows_by = match_windows_by.TITLE,
        missing_window_policy = missing_window_policy.MATCH_TITLE_OR_OPEN_NEW_WINDOW,
        unmatched_window_action = unmatched_window_action.OPEN_NEW_WINDOW,
        hidden_application_windows = hidden_application_windows.LEAVE_OUT,
        preview_method = preview_method.BLURRED_SNAPSHOTS,
        preview_blur = 1,
        preview_size = { w = 0.1, h = 0.1 },
        list_font_size = 0.012,
        list_layout = list_layout.COLUMNS,
        list_sizing = list_sizing.FILL_SCREEN,
        title_overflow = title_overflow.WRAP,
        title_line_count = 2,
        builtin_screen_name_patterns = { "^Built%-in", "内建", "內建" },
        timing = {
            poll_interval_seconds = 0.05,
            modifier_release_timeout_seconds = 3,
            desktop_show_timeout_seconds = 5,
            desktop_press_retry_seconds = 2,
            desktop_settle_seconds = 0.1,
            minimize_timeout_seconds = 2,
            window_settle_seconds = 0.3,
            window_move_timeout_seconds = 1,
            window_reach_timeout_seconds = 1,
            busy_watchdog_seconds = 90,
            mission_control_timeout_seconds = 3,
            mission_control_press_gap_seconds = 0.4,
            application_launch_timeout_seconds = 10,
            application_focus_timeout_seconds = 1,
            save_delay_seconds = 2,
            periodic_save_seconds = 60,
            screen_settle_seconds = 3,
            snapshot_time_limit_seconds = 0.5,
        },
    }
end

return default_settings
