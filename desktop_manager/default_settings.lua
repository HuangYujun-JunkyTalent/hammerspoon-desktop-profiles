local concealment_method = require("desktop_manager.core.concealment_method")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local preview_method = require("desktop_manager.core.preview_method")
local monitor_matching = require("desktop_manager.core.monitor_matching")

local default_settings = {}

---@class Timing
---@field poll_interval_seconds number
---@field modifier_release_timeout_seconds number
---@field desktop_switch_timeout_seconds number
---@field desktop_settle_seconds number
---@field minimize_timeout_seconds number
---@field window_settle_seconds number
---@field mission_control_timeout_seconds number
---@field mission_control_press_gap_seconds number
---@field application_launch_timeout_seconds number
---@field save_delay_seconds number
---@field periodic_save_seconds number
---@field screen_settle_seconds number
---@field snapshot_time_limit_seconds number a slower snapshot stops the snapshots until a reload

---@class Settings
---@field state_file_path string
---@field profile_count integer
---@field hotkey_modifiers string[]
---@field app_hotkey_modifiers string[] the modifiers that, with a number, reach an application.
---Control-Option takes no shortcut of macOS or of the running applications, while Command takes
---the tabs and views of many applications and Command-Shift takes the screenshots of macOS.
---@field app_number_count integer
---@field url_event_name string
---@field initial_monitor_matching string
---@field concealment_method string a value of concealment_method
---@field missing_window_policy string a value of missing_window_policy
---@field preview_method string a value of preview_method
---@field builtin_screen_name_patterns string[]
---@field timing Timing

---@param state_file_path string
---@return Settings
function default_settings.create(state_file_path)
    return {
        state_file_path = state_file_path,
        profile_count = 9,
        hotkey_modifiers = { "cmd", "alt", "shift" },
        app_hotkey_modifiers = { "ctrl", "alt" },
        app_number_count = 9,
        url_event_name = "desktop-manager",
        initial_monitor_matching = monitor_matching.BY_COUNT,
        concealment_method = concealment_method.MINIMIZE_WINDOWS,
        missing_window_policy = missing_window_policy.MATCH_TITLE_OR_OPEN_NEW_WINDOW,
        preview_method = preview_method.BLURRED_SNAPSHOTS,
        builtin_screen_name_patterns = { "^Built%-in", "内建", "內建" },
        timing = {
            poll_interval_seconds = 0.05,
            modifier_release_timeout_seconds = 3,
            desktop_switch_timeout_seconds = 2,
            desktop_settle_seconds = 0.1,
            minimize_timeout_seconds = 2,
            window_settle_seconds = 0.3,
            mission_control_timeout_seconds = 3,
            mission_control_press_gap_seconds = 0.4,
            application_launch_timeout_seconds = 10,
            save_delay_seconds = 2,
            periodic_save_seconds = 60,
            screen_settle_seconds = 3,
            snapshot_time_limit_seconds = 0.5,
        },
    }
end

return default_settings
