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

---A simulated Control-number would combine with modifiers that the user still holds.
---@param timing Timing
---@param on_done fun()
function keyboard_modifiers.wait_for_release(timing, on_done)
    poll_until.wait(
        keyboard_modifiers.are_released,
        timing.modifier_release_timeout_seconds,
        timing.poll_interval_seconds,
        function()
            on_done()
        end
    )
end

return keyboard_modifiers
