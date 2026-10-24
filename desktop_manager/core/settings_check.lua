---The checks of the settings of the desktop manager that run before it starts.
local concealment_method = require("desktop_manager.core.concealment_method")
local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")
local highlight_colors = require("desktop_manager.core.highlight_colors")
local list_layout = require("desktop_manager.core.list_layout")
local list_sizing = require("desktop_manager.core.list_sizing")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local preview_method = require("desktop_manager.core.preview_method")
local title_overflow = require("desktop_manager.core.title_overflow")
local unmatched_window_action = require("desktop_manager.core.unmatched_window_action")

local settings_check = {}

---@alias SettingCheck fun(settings: Settings): string|nil the message of a faulty setting

---@param name string the name of the setting
---@param values table the module of the closed set of the values, with its `is_valid`
---@param noun string what a value of the setting names
---@return SettingCheck
local function build_closed_set_check(name, values, noun)
    return function(settings)
        if values.is_valid(settings[name]) then
            return nil
        end
        return string.format(
            "the setting %s is %q, which names no %s",
            name,
            tostring(settings[name]),
            noun
        )
    end
end

---@type SettingCheck
local function check_preview_size(settings)
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
        return "the setting preview_size must give w and h as fractions of the screen,"
            .. " above 0 and at most 1"
    end
    return nil
end

---@type SettingCheck
local function check_list_font_size(settings)
    if
        type(settings.list_font_size) ~= "number"
        or settings.list_font_size <= 0
        or settings.list_font_size > 0.1
    then
        return string.format(
            "the setting list_font_size is %s, and it must be a fraction of the height of the"
                .. " screen, above 0 and at most 0.1",
            tostring(settings.list_font_size)
        )
    end
    return nil
end

---@type SettingCheck
local function check_title_line_count(settings)
    if math.type(settings.title_line_count) ~= "integer" or settings.title_line_count < 1 then
        return string.format(
            "the setting title_line_count is %s, and it must be a whole number of 1 or more",
            tostring(settings.title_line_count)
        )
    end
    return nil
end

---@type SettingCheck
local function check_preview_blur(settings)
    if type(settings.preview_blur) ~= "number" or settings.preview_blur < 1 then
        return string.format(
            "the setting preview_blur is %s, and it must be a number of 1 or more",
            tostring(settings.preview_blur)
        )
    end
    return nil
end

---@type SettingCheck
local function check_pause_after_macos_start_seconds(settings)
    local seconds = settings.pause_after_macos_start_seconds
    if type(seconds) ~= "number" or seconds < 0 then
        return string.format(
            "the setting pause_after_macos_start_seconds is %s, and it must be a number of seconds"
                .. " of 0 or more",
            tostring(seconds)
        )
    end
    return nil
end

---@type SettingCheck
local function check_search_highlight_colors(settings)
    local _, message = highlight_colors.complete(settings.search_highlight_colors)
    return message
end

---The former values of each setting that has some, with the value that takes the place of each.
---@type table<string, table<string, string>>
local OLD_VALUES_BY_SETTING = {
    missing_window_policy = missing_window_policy.OLD_VALUES,
}

---@param settings Settings
---@return Settings replaced a copy of the settings, with each former value of a setting replaced
---by the value that takes its place
---@return string[] lines one line for each replaced value, which names the value that takes its
---place
function settings_check.replace_old_values(settings)
    local replaced, lines = {}, {}
    for name, value in pairs(settings) do
        replaced[name] = value
    end
    for name, old_values in pairs(OLD_VALUES_BY_SETTING) do
        local new_value = old_values[settings[name]]
        if new_value then
            replaced[name] = new_value
            table.insert(
                lines,
                string.format(
                    "the setting %s is %q, the old name of %q",
                    name,
                    settings[name],
                    new_value
                )
            )
        end
    end
    return replaced, lines
end

---The checks in the order in which they run, so that the message names the first faulty setting.
---@type SettingCheck[]
local CHECKS = {
    check_preview_size,
    check_list_font_size,
    build_closed_set_check("title_overflow", title_overflow, "way"),
    check_title_line_count,
    build_closed_set_check("list_sizing", list_sizing, "sizing"),
    build_closed_set_check("list_layout", list_layout, "layout"),
    check_preview_blur,
    build_closed_set_check("preview_method", preview_method, "method"),
    check_search_highlight_colors,
    build_closed_set_check("match_windows_by", match_windows_by, "way to match windows"),
    build_closed_set_check("missing_window_policy", missing_window_policy, "policy"),
    build_closed_set_check("unmatched_window_action", unmatched_window_action, "action"),
    build_closed_set_check("hidden_application_windows", hidden_application_windows, "choice"),
    build_closed_set_check("concealment_method", concealment_method, "concealment method"),
    check_pause_after_macos_start_seconds,
}

---@param settings Settings
---@return Settings|nil checked a copy of the settings, with the colors that the setting
---`search_highlight_colors` leaves out filled with the defaults
---@return string|nil message the message of the first faulty setting
function settings_check.check(settings)
    for _, check in ipairs(CHECKS) do
        local message = check(settings)
        if message then
            return nil, message
        end
    end
    local checked = {}
    for name, value in pairs(settings) do
        checked[name] = value
    end
    checked.search_highlight_colors = highlight_colors.complete(settings.search_highlight_colors)
    return checked, nil
end

return settings_check
