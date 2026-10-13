local concealment_method = require("desktop_manager.core.concealment_method")
local list_layout = require("desktop_manager.core.list_layout")
local list_sizing = require("desktop_manager.core.list_sizing")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local preview_method = require("desktop_manager.core.preview_method")
local title_overflow = require("desktop_manager.core.title_overflow")
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
---@field app_number_count integer
---@field url_event_name string
---@field initial_monitor_matching string
---@field concealment_method string a value of concealment_method
---@field match_windows_by string a value of match_windows_by
---@field missing_window_policy string a value of missing_window_policy
---@field search_highlight_colors table|nil the colors of highlight_colors that replace the
---defaults, by name, such as `{ selection = { hex = "#2E8B57", alpha = 0.9 } }`
---@field preview_method string a value of preview_method
---@field preview_blur number 1 or more: a preview keeps 1 / preview_blur of the detail of its size
---@field preview_size table the w and h of a preview, as fractions of the width and height of the
---screen in front
---@field list_font_size number the size of the titles, as a fraction of the height of the screen
---in front
---@field list_layout string a value of list_layout
---@field list_sizing string a value of list_sizing
---@field title_overflow string a value of title_overflow
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
