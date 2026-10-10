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

---@class Settings
---@field state_file_path string
---@field profile_count integer
---@field hotkey_modifiers string[]
---@field url_event_name string
---@field initial_monitor_matching string
---@field builtin_screen_name_patterns string[]
---@field timing Timing

---@param state_file_path string
---@return Settings
function default_settings.create(state_file_path)
    return {
        state_file_path = state_file_path,
        profile_count = 9,
        hotkey_modifiers = { "cmd", "alt", "shift" },
        url_event_name = "desktop-manager",
        initial_monitor_matching = monitor_matching.BY_COUNT,
        builtin_screen_name_patterns = { "^Built%-in", "内建", "內建" },
        timing = {
            poll_interval_seconds = 0.05,
            modifier_release_timeout_seconds = 3,
            desktop_switch_timeout_seconds = 2,
            desktop_settle_seconds = 0.3,
            minimize_timeout_seconds = 2,
            window_settle_seconds = 0.3,
            mission_control_timeout_seconds = 3,
            mission_control_press_gap_seconds = 0.4,
            application_launch_timeout_seconds = 10,
            save_delay_seconds = 2,
            periodic_save_seconds = 60,
            screen_settle_seconds = 3,
        },
    }
end

return default_settings
