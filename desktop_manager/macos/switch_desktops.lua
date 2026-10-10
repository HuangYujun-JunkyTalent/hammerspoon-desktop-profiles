local keyboard_modifiers = require("desktop_manager.macos.keyboard_modifiers")
local poll_until = require("desktop_manager.macos.poll_until")
local read_desktops = require("desktop_manager.macos.read_desktops")
local retained_timers = require("desktop_manager.macos.retained_timers")

local switch_desktops = {}

local KEY_PRESS_MICROSECONDS = 20000
local HIGHEST_SHORTCUT_NUMBER = 9
local SHORTCUT_SETTING_HINT = 'Turn on "Switch to Desktop %d" in System Settings,'
    .. " Keyboard, Keyboard Shortcuts, Mission Control."

---Shows a desktop by pressing the macOS shortcut "Switch to Desktop N", Control-N.
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
    if not shortcut_number or shortcut_number > HIGHEST_SHORTCUT_NUMBER then
        on_done(
            string.format(
                "desktop %d is number %s in Mission Control, and only 1 to 9 have a shortcut",
                space_id,
                tostring(shortcut_number)
            )
        )
        return
    end
    keyboard_modifiers.wait_for_release(timing, function()
        hs.eventtap.keyStroke({ "ctrl" }, tostring(shortcut_number), KEY_PRESS_MICROSECONDS)
        poll_until.wait(
            function()
                return read_desktops.is_space_active(space_id)
            end,
            timing.desktop_switch_timeout_seconds,
            timing.poll_interval_seconds,
            function(is_active)
                if not is_active then
                    on_done(
                        string.format(
                            "Control-%d did not show desktop %d. %s",
                            shortcut_number,
                            shortcut_number,
                            string.format(SHORTCUT_SETTING_HINT, shortcut_number)
                        )
                    )
                    return
                end
                retained_timers.after(timing.desktop_settle_seconds, function()
                    on_done(nil)
                end)
            end
        )
    end)
end

return switch_desktops
