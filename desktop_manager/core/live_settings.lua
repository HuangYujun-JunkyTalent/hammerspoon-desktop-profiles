local concealment_method = require("desktop_manager.core.concealment_method")
local deep_copy = require("desktop_manager.core.deep_copy")
local enumeration = require("desktop_manager.core.enumeration")
local hidden_application_windows = require("desktop_manager.core.hidden_application_windows")
local list_layout = require("desktop_manager.core.list_layout")
local list_sizing = require("desktop_manager.core.list_sizing")
local match_windows_by = require("desktop_manager.core.match_windows_by")
local missing_window_policy = require("desktop_manager.core.missing_window_policy")
local monitor_matching = require("desktop_manager.core.monitor_matching")
local preview_method = require("desktop_manager.core.preview_method")
local settings_check = require("desktop_manager.core.settings_check")
local title_overflow = require("desktop_manager.core.title_overflow")
local unmatched_window_action = require("desktop_manager.core.unmatched_window_action")

---The settings that the window "Settings…" changes while the desktop manager runs.
---A choice of the window is an override, which the state saves over the value of
---`default_settings.lua`, and the value of the file comes back when the override goes.
---The monitor matching is the one option that the state holds in a field of its own, because the
---state recorded it before the window existed.
local live_settings = {}

---What the window shows for a setting: a choice among named values, a number on a slider, or a
---width and a height on two sliders.
live_settings.KIND = enumeration.define({
    CHOICE = "choice",
    NUMBER = "number",
    SIZE = "size",
})

---@alias LiveSettingKind "choice"|"number"|"size"

---The sections of the window, by their titles, in the order of the window.
live_settings.SECTION = enumeration.define({
    SWITCHING = "Switching profiles",
    MONITORS_AND_LOGIN = "Monitors and login",
    CONTENT = "What the list and the search show",
    LAYOUT = "Layout of the list",
})

---@class LiveSettingChoice
---@field value string
---@field label string

---@class LiveSetting
---@field name string the name of the setting in `default_settings.lua`, or `monitor_matching`
---@field section string a value of live_settings.SECTION
---@field label string
---@field description string
---@field kind LiveSettingKind
---@field choices LiveSettingChoice[]|nil the values of a choice, in the order of the window
---@field minimum number|nil the least value of a number or of each side of a size
---@field maximum number|nil the greatest value of a number or of each side of a size
---@field step number|nil the step of the slider
---@field is_integer boolean|nil whether a number is a whole number
---@field is_kept_in_state boolean|nil whether the state holds the value in a field of its own

---The settings of the window, in the order of the window.
---@type LiveSetting[]
live_settings.ENTRIES = {
    {
        name = "unmatched_window_action",
        section = live_settings.SECTION.SWITCHING,
        label = "A window that is no longer open",
        description = "A window that the profile recorded in sight, with no open window to match",
        kind = live_settings.KIND.CHOICE,
        choices = {
            {
                value = unmatched_window_action.OPEN_NEW_WINDOW,
                label = "Open a new window of its app in its place",
            },
            { value = unmatched_window_action.FORGET, label = "Remove it from the profile" },
        },
    },
    {
        name = "match_windows_by",
        section = live_settings.SECTION.SWITCHING,
        label = "Recognize a window by",
        description = "How a switch finds the open window of each window that the profile recorded",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = match_windows_by.TITLE, label = "Its title, then its window id" },
            { value = match_windows_by.ID, label = "Its window id" },
        },
    },
    {
        name = "missing_window_policy",
        section = live_settings.SECTION.SWITCHING,
        label = "A reopened window",
        description = "A new window with the app and the title of a window that closed",
        kind = live_settings.KIND.CHOICE,
        choices = {
            {
                value = missing_window_policy.MATCH_TITLE,
                label = "Takes the place of the closed one",
            },
            { value = missing_window_policy.MATCH_ID_ALONE, label = "Counts as a new window" },
        },
    },
    {
        name = "concealment_method",
        section = live_settings.SECTION.SWITCHING,
        label = "Windows of the other profiles",
        description = "How a switch puts away the windows that the new profile does not hold",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = concealment_method.MINIMIZE_WINDOWS, label = "Minimize them" },
            {
                value = concealment_method.HIDE_APPLICATIONS,
                label = "Hide their app once all its windows are put away",
            },
        },
    },
    {
        name = "monitor_matching",
        section = live_settings.SECTION.MONITORS_AND_LOGIN,
        label = "Same monitor setup when",
        description = "A profile keeps one layout for each monitor setup",
        kind = live_settings.KIND.CHOICE,
        choices = {
            {
                value = monitor_matching.BY_COUNT,
                label = "The number of external monitors is the same",
            },
            {
                value = monitor_matching.BY_IDENTITY,
                label = "Each external monitor has the same name",
            },
        },
        is_kept_in_state = true,
    },
    {
        name = "pause_after_login_seconds",
        section = live_settings.SECTION.MONITORS_AND_LOGIN,
        label = "Pause after a login, in seconds",
        description = "Hammerspoon starting this soon after a login pauses the active profile,"
            .. " and 0 never pauses it",
        kind = live_settings.KIND.NUMBER,
        minimum = 0,
        maximum = 1800,
        step = 30,
        is_integer = true,
    },
    {
        name = "hidden_application_windows",
        section = live_settings.SECTION.CONTENT,
        label = "Windows of hidden apps",
        description = "Choosing one of them unhides its app",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = hidden_application_windows.LEAVE_OUT, label = "Leave them out" },
            {
                value = hidden_application_windows.LIST_WHERE_FOUND,
                label = "Show the ones that macOS still lists",
            },
            { value = hidden_application_windows.LIST_ALL, label = "Show all of them" },
        },
    },
    {
        name = "preview_method",
        section = live_settings.SECTION.CONTENT,
        label = "Preview of a window",
        description = "What shows beside the title of each window",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = preview_method.BLURRED_SNAPSHOTS, label = "A blurred image of the window" },
            { value = preview_method.APP_ICONS, label = "The icon of its app" },
        },
    },
    {
        name = "preview_size",
        section = live_settings.SECTION.CONTENT,
        label = "Size of a preview",
        description = "Width and height, as a share of the screen in front",
        kind = live_settings.KIND.SIZE,
        minimum = 0.03,
        maximum = 0.3,
        step = 0.005,
    },
    {
        name = "preview_blur",
        section = live_settings.SECTION.CONTENT,
        label = "Blur of a preview",
        description = "1 is sharp, 2 keeps half of the detail, 4 a quarter",
        kind = live_settings.KIND.NUMBER,
        minimum = 1,
        maximum = 8,
        step = 0.5,
    },
    {
        name = "list_layout",
        section = live_settings.SECTION.LAYOUT,
        label = "Arrangement",
        description = "How the list of Control-Option places the apps",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = list_layout.COLUMNS, label = "One column per app" },
            { value = list_layout.COLUMNS_PER_DISPLAY, label = "One column per app, by display" },
            { value = list_layout.ROWS, label = "One row per app, with its windows below" },
        },
    },
    {
        name = "list_sizing",
        section = live_settings.SECTION.LAYOUT,
        label = "Size",
        description = "Whether the list grows to use the screen",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = list_sizing.FILL_SCREEN, label = "Grow to fill the screen" },
            { value = list_sizing.FIXED, label = "Keep the sizes set here" },
        },
    },
    {
        name = "list_font_size",
        section = live_settings.SECTION.LAYOUT,
        label = "Size of the titles",
        description = "As a share of the height of the screen in front",
        kind = live_settings.KIND.NUMBER,
        minimum = 0.006,
        maximum = 0.03,
        step = 0.0005,
    },
    {
        name = "title_overflow",
        section = live_settings.SECTION.LAYOUT,
        label = "A long title",
        description = "A title longer than its space",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = title_overflow.WRAP, label = "Wraps onto more lines" },
            { value = title_overflow.TRUNCATE, label = "Ends with an ellipsis" },
            { value = title_overflow.SCROLL, label = "Scrolls while its window is selected" },
        },
    },
    {
        name = "title_line_count",
        section = live_settings.SECTION.LAYOUT,
        label = "Lines of a wrapped title",
        description = "The most lines that a long title wraps onto",
        kind = live_settings.KIND.NUMBER,
        minimum = 1,
        maximum = 6,
        step = 1,
        is_integer = true,
    },
}

---@type table<string, LiveSetting>
local ENTRY_BY_NAME = {}
for _, entry in ipairs(live_settings.ENTRIES) do
    ENTRY_BY_NAME[entry.name] = entry
end

---@param name string
---@return LiveSetting|nil
function live_settings.find(name)
    return ENTRY_BY_NAME[name]
end

---@param entry LiveSetting
---@param value any
---@return number|nil the value, a whole number for a setting of whole numbers, or nil when the
---value lies outside the range of the slider
local function read_number(entry, value)
    if type(value) ~= "number" or value < entry.minimum or value > entry.maximum then
        return nil
    end
    if entry.is_integer then
        return math.tointeger(value)
    end
    return value
end

---@type table<LiveSettingKind, fun(entry: LiveSetting, value: any): any>
local READ_VALUE_BY_KIND = {
    [live_settings.KIND.CHOICE] = function(entry, value)
        for _, choice in ipairs(entry.choices) do
            if choice.value == value then
                return value
            end
        end
        return nil
    end,
    [live_settings.KIND.NUMBER] = read_number,
    [live_settings.KIND.SIZE] = function(entry, value)
        if type(value) ~= "table" then
            return nil
        end
        local width, height = read_number(entry, value.w), read_number(entry, value.h)
        if not width or not height then
            return nil
        end
        return { w = width, h = height }
    end,
}

---@param entry LiveSetting
---@param value any a value from the page of the window or from the saved state
---@return any|nil the value in the shape of the setting, or nil when the window offers no such
---value
function live_settings.read_value(entry, value)
    return READ_VALUE_BY_KIND[entry.kind](entry, value)
end

---Reads the overrides of a state decoded from JSON, and drops each override of a setting that the
---window does not change or whose value the window does not offer.
---@param raw any
---@return table<string, any> overrides by the name of the setting
function live_settings.decode(raw)
    local overrides = {}
    if type(raw) ~= "table" then
        return overrides
    end
    for _, entry in ipairs(live_settings.ENTRIES) do
        if not entry.is_kept_in_state and raw[entry.name] ~= nil then
            overrides[entry.name] = live_settings.read_value(entry, raw[entry.name])
        end
    end
    return overrides
end

local LEFT_OUT_PREFIX = "the saved choice of the window Settings is left out: "

---Puts the overrides over the settings of the file, in the order of the window.
---An override that the checks of the settings refuse together with the others is left out.
---@param base Settings the checked settings of `default_settings.lua`
---@param overrides table<string, any>
---@return Settings settings the checked settings with the overrides
---@return table<string, any> kept the overrides that the settings took
---@return string[] lines one line for each override left out, with the reason
function live_settings.apply(base, overrides)
    local settings = base
    local kept, lines = {}, {}
    for _, entry in ipairs(live_settings.ENTRIES) do
        local value = overrides[entry.name]
        if value ~= nil and not entry.is_kept_in_state then
            local candidate = deep_copy.copy(settings)
            candidate[entry.name] = deep_copy.copy(value)
            local checked, message = settings_check.check(candidate)
            if checked then
                settings = checked
                kept[entry.name] = deep_copy.copy(value)
            else
                table.insert(lines, LEFT_OUT_PREFIX .. message)
            end
        end
    end
    return settings, kept, lines
end

return live_settings
