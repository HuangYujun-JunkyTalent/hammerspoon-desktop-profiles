local desktop_shortcuts = require("desktop_manager.core.desktop_shortcuts")
local keyboard_modifiers = require("desktop_manager.macos.keyboard_modifiers")
local macos_shortcut_settings = require("keyboard_shortcuts.macos.macos_shortcut_settings")
local poll_until = require("desktop_manager.macos.poll_until")
local read_desktops = require("desktop_manager.macos.read_desktops")
local retained_timers = require("desktop_manager.macos.retained_timers")

local switch_desktops = {}

local KEY_PRESS_MICROSECONDS = 20000
local SHORTCUT_SETTING_HINT = 'Turn on "Switch to Desktop %d" in System Settings,'
    .. " Keyboard, Keyboard Shortcuts, Mission Control, or run"
    .. ' "make enable-desktop-shortcuts" in the repository of the desktop manager.'

local log = nil

---@return table an hs.logger, made at the first switch, because the tests load this module without
---Hammerspoon
local function get_log()
    log = log or hs.logger.new("desktop_sw", "info")
    return log
end

local read_symbolic_hotkeys = macos_shortcut_settings.read_symbolic_hotkeys

---The script that turns on the shortcuts 1 to 10, found from the path of this file.
local ENABLE_SHORTCUTS_SCRIPT = (
    debug.getinfo(1, "S").source:match("^@(.*)/desktop_manager/macos/switch_desktops%.lua$") or "."
) .. "/tools/enable_desktop_shortcuts.sh"

---Turns on "Switch to Desktop 1" to "Switch to Desktop 10" with the script of the repository, and
---waits until macOS reports the shortcut that the switch needs.
---@param shortcut_number integer
---@param timing Timing
---@param on_done fun(is_on: boolean)
local function turn_on_shortcuts(shortcut_number, timing, on_done)
    get_log().f(
        'turning on "Switch to Desktop 1" to "Switch to Desktop 10", because desktop %d has none',
        shortcut_number
    )
    hs.task
        .new("/bin/sh", function(exit_code, _, standard_error)
            if exit_code ~= 0 then
                get_log().w("the shortcuts could not be turned on: " .. tostring(standard_error))
                on_done(false)
                return
            end
            poll_until.wait(function()
                local symbolic_hotkeys = read_symbolic_hotkeys()
                return symbolic_hotkeys ~= nil
                    and desktop_shortcuts.is_on(symbolic_hotkeys, shortcut_number)
            end, timing.desktop_switch_timeout_seconds, timing.poll_interval_seconds, on_done)
        end, { ENABLE_SHORTCUTS_SCRIPT })
        :start()
end

---Presses the modifiers of desktop_shortcuts with N, or with 0 for desktop 10, once the user
---releases the modifiers, and waits
---until the desktop shows.
---@param space_id integer
---@param shortcut_number integer
---@param timing Timing
---@param is_shortcut_known_on boolean whether macOS reported the shortcut as on before the press
---@param on_done fun(error_message: string|nil)
local function press_shortcut(space_id, shortcut_number, timing, is_shortcut_known_on, on_done)
    local requested_at = hs.timer.secondsSinceEpoch()
    keyboard_modifiers.wait_for_release(timing, function()
        local pressed_at = hs.timer.secondsSinceEpoch()
        local key = desktop_shortcuts.key_of(shortcut_number)
        hs.eventtap.keyStroke(desktop_shortcuts.MODIFIERS, key, KEY_PRESS_MICROSECONDS)
        poll_until.wait(
            function()
                return read_desktops.is_space_active(space_id)
            end,
            timing.desktop_switch_timeout_seconds,
            timing.poll_interval_seconds,
            function(is_active)
                get_log().f(
                    "desktop %d: %.2f seconds for the release of the modifiers,"
                        .. " %.2f seconds until macOS reported it",
                    shortcut_number,
                    pressed_at - requested_at,
                    hs.timer.secondsSinceEpoch() - pressed_at
                )
                if not is_active then
                    local message = string.format(
                        "%s-%s did not show desktop %d within %g seconds.",
                        desktop_shortcuts.MODIFIER_TEXT,
                        key,
                        shortcut_number,
                        timing.desktop_switch_timeout_seconds
                    )
                    if not is_shortcut_known_on then
                        message = message
                            .. " "
                            .. string.format(SHORTCUT_SETTING_HINT, shortcut_number)
                    end
                    on_done(message)
                    return
                end
                retained_timers.after(timing.desktop_settle_seconds, function()
                    on_done(nil)
                end)
            end
        )
    end)
end

---Shows a desktop by pressing the macOS shortcut "Switch to Desktop N", the modifiers of
---desktop_shortcuts with N, or with 0 for
---desktop 10.
---System Settings lists the shortcut of a desktop only while the desktop exists, so a desktop that
---a monitor adds can lack it, and the switch then turns the shortcuts on before the press.
---`on_done` receives nil once the desktop is active, or a message that says why it is not.
---@param space_id integer
---@param timing Timing
---@param on_done fun(error_message: string|nil)
function switch_desktops.switch_to_space(space_id, timing, on_done)
    if read_desktops.is_space_active(space_id) then
        on_done(nil)
        return
    end
    local shortcut_number = read_desktops.find_desktop_shortcut_number(space_id)
    if not shortcut_number or shortcut_number > desktop_shortcuts.HIGHEST_NUMBER then
        on_done(
            string.format(
                "desktop %d is number %s in Mission Control, and only 1 to %d have a shortcut",
                space_id,
                tostring(shortcut_number),
                desktop_shortcuts.HIGHEST_NUMBER
            )
        )
        return
    end
    local symbolic_hotkeys = read_symbolic_hotkeys()
    if symbolic_hotkeys == nil or desktop_shortcuts.is_on(symbolic_hotkeys, shortcut_number) then
        press_shortcut(space_id, shortcut_number, timing, symbolic_hotkeys ~= nil, on_done)
        return
    end
    turn_on_shortcuts(shortcut_number, timing, function(is_on)
        if not is_on then
            on_done(
                string.format(
                    "desktop %d cannot be shown, because its shortcut is off"
                        .. " and could not be turned on. %s",
                    shortcut_number,
                    string.format(SHORTCUT_SETTING_HINT, shortcut_number)
                )
            )
            return
        end
        press_shortcut(space_id, shortcut_number, timing, true, on_done)
    end)
end

return switch_desktops
