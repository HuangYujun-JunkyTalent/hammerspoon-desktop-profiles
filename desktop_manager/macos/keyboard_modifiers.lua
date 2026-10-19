---Reads the modifier keys that the user holds.
---The list of the application numbers shows while the user holds the modifiers of its shortcut, and
---Mission Control opens once the user has released every modifier key.
local poll_until = require("desktop_manager.macos.poll_until")

local keyboard_modifiers = {}

local MODIFIER_KEYS = { "cmd", "alt", "shift", "ctrl" }

---@return boolean
function keyboard_modifiers.are_released()
    local held = hs.eventtap.checkKeyboardModifiers()
    for _, key in ipairs(MODIFIER_KEYS) do
        if held[key] then
            return false
        end
    end
    return true
end

---@param flags table<string, boolean> the modifiers held, as hs.eventtap reports them
---@param modifiers string[]
---@return boolean whether every one of the modifiers is in the flags
function keyboard_modifiers.are_all_in(flags, modifiers)
    for _, modifier in ipairs(modifiers) do
        if not flags[modifier] then
            return false
        end
    end
    return true
end

---@param modifiers string[]
---@return boolean whether the user holds every one of the modifiers now
function keyboard_modifiers.are_held(modifiers)
    return keyboard_modifiers.are_all_in(hs.eventtap.checkKeyboardModifiers(), modifiers)
end

---Waits until the user releases every modifier key, before Mission Control opens, because Option
---held in Mission Control turns the thumbnails into buttons that remove desktops.
---@param timing Timing
---@param on_done fun(are_released: boolean) false when a key stays held past the time limit
function keyboard_modifiers.wait_for_release(timing, on_done)
    poll_until.wait(
        keyboard_modifiers.are_released,
        timing.modifier_release_timeout_seconds,
        timing.poll_interval_seconds,
        on_done
    )
end

return keyboard_modifiers
