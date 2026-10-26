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

live_settings.SECTION = enumeration.define({
    SWITCHES = "Switches",
    LIST_AND_SEARCH = "List and search",
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

---@type LiveSettingChoice[]
local MONITOR_MATCHING_CHOICES = {}
for _, matching in ipairs(monitor_matching.all()) do
    table.insert(MONITOR_MATCHING_CHOICES, {
        value = matching,
        label = monitor_matching.label_of(matching),
    })
end

---The settings of the window, in the order of the window.
---@type LiveSetting[]
live_settings.ENTRIES = {
    {
        name = "unmatched_window_action",
        section = live_settings.SECTION.SWITCHES,
        label = "A recorded window that is gone",
        description = "What a switch does for a recorded window in sight that no open window"
            .. " matches",
        kind = live_settings.KIND.CHOICE,
        choices = {
            {
                value = unmatched_window_action.OPEN_NEW_WINDOW,
                label = "Open a new window of the application at the recorded place",
            },
            {
                value = unmatched_window_action.FORGET,
                label = "Open nothing and remove the window from the profile",
            },
        },
    },
    {
        name = "match_windows_by",
        section = live_settings.SECTION.SWITCHES,
        label = "Pair a record with an open window by",
        description = "What a switch tries first when it pairs a recorded window with an open one",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = match_windows_by.TITLE, label = "Title, then window id" },
            { value = match_windows_by.ID, label = "Window id" },
        },
    },
    {
        name = "missing_window_policy",
        section = live_settings.SECTION.SWITCHES,
        label = "A reopened window",
        description = "Whether a window of the same application with the same title takes the"
            .. " records of a closed window",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = missing_window_policy.MATCH_TITLE, label = "Takes the records by its title" },
            { value = missing_window_policy.MATCH_ID_ALONE, label = "Counts as a new window" },
        },
    },
    {
        name = "concealment_method",
        section = live_settings.SECTION.SWITCHES,
        label = "Windows of another profile",
        description = "How a switch takes a window out of sight",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = concealment_method.MINIMIZE_WINDOWS, label = "Minimize the windows" },
            {
                value = concealment_method.HIDE_APPLICATIONS,
                label = "Hide an application once all its windows go out of sight",
            },
        },
    },
    {
        name = "monitor_matching",
        section = live_settings.SECTION.SWITCHES,
        label = "Same monitor configuration by",
        description = "When two monitor configurations share the records of a profile",
        kind = live_settings.KIND.CHOICE,
        choices = MONITOR_MATCHING_CHOICES,
        is_kept_in_state = true,
    },
    {
        name = "pause_after_login_seconds",
        section = live_settings.SECTION.SWITCHES,
        label = "Pause after a login, in seconds",
        description = "A start of Hammerspoon this soon after a login pauses the active profile,"
            .. " and 0 never pauses it",
        kind = live_settings.KIND.NUMBER,
        minimum = 0,
        maximum = 1800,
        step = 30,
        is_integer = true,
    },
    {
        name = "hidden_application_windows",
        section = live_settings.SECTION.LIST_AND_SEARCH,
        label = "Windows of hidden applications",
        description = "Which windows of a hidden application the list and the search show",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = hidden_application_windows.LEAVE_OUT, label = "None" },
            {
                value = hidden_application_windows.LIST_WHERE_FOUND,
                label = "The standard windows and those on desktops out of view",
            },
            { value = hidden_application_windows.LIST_ALL, label = "Every window" },
        },
    },
    {
        name = "list_layout",
        section = live_settings.SECTION.LIST_AND_SEARCH,
        label = "Layout of the list",
        description = "How the list of Control-Option arranges the applications",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = list_layout.COLUMNS, label = "A column per application" },
            { value = list_layout.COLUMNS_PER_DISPLAY, label = "Columns grouped by display" },
            { value = list_layout.ROWS, label = "A line per application and per window" },
        },
    },
    {
        name = "list_sizing",
        section = live_settings.SECTION.LIST_AND_SEARCH,
        label = "Size of the list",
        description = "How the list uses the screen",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = list_sizing.FILL_SCREEN, label = "Grow to fill the screen" },
            { value = list_sizing.FIXED, label = "Keep the sizes below" },
        },
    },
    {
        name = "preview_method",
        section = live_settings.SECTION.LIST_AND_SEARCH,
        label = "Beside a title",
        description = "What the list and the search show for a window",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = preview_method.BLURRED_SNAPSHOTS, label = "A blurred image of the window" },
            { value = preview_method.APP_ICONS, label = "The icon of the application" },
        },
    },
    {
        name = "preview_size",
        section = live_settings.SECTION.LIST_AND_SEARCH,
        label = "Size of a preview",
        description = "The width and the height, as fractions of the screen in front",
        kind = live_settings.KIND.SIZE,
        minimum = 0.03,
        maximum = 0.3,
        step = 0.005,
    },
    {
        name = "preview_blur",
        section = live_settings.SECTION.LIST_AND_SEARCH,
        label = "Blur of a preview",
        description = "1 keeps full detail, 2 half of it, 4 a quarter",
        kind = live_settings.KIND.NUMBER,
        minimum = 1,
        maximum = 8,
        step = 0.5,
    },
    {
        name = "list_font_size",
        section = live_settings.SECTION.LIST_AND_SEARCH,
        label = "Size of the titles",
        description = "As a fraction of the height of the screen in front",
        kind = live_settings.KIND.NUMBER,
        minimum = 0.006,
        maximum = 0.03,
        step = 0.0005,
    },
    {
        name = "title_overflow",
        section = live_settings.SECTION.LIST_AND_SEARCH,
        label = "A long title",
        description = "What happens to a title longer than its space",
        kind = live_settings.KIND.CHOICE,
        choices = {
            { value = title_overflow.WRAP, label = "Flows over several lines" },
            { value = title_overflow.TRUNCATE, label = "Ends in an ellipsis" },
            { value = title_overflow.SCROLL, label = "Scrolls while its window is selected" },
        },
    },
    {
        name = "title_line_count",
        section = live_settings.SECTION.LIST_AND_SEARCH,
        label = "Lines of a long title",
        description = "The most lines of a title that flows over several lines",
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
