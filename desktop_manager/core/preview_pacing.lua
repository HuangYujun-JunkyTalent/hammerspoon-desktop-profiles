---When the next preview of the list or the search may start.
---A preview starts after the list or the panel has had the time to draw, and only once the input
---has paused, because a snapshot holds the main thread of Hammerspoon, so that a key waits for at
---most one snapshot.
local preview_pacing = {
    ---A timer due this long after the panel shows lets the run loop of Hammerspoon draw the panel
    ---first, because a timer of 0 seconds may fire before the drawing, and one frame at 60 Hz takes
    ---about 0.017 seconds.
    AFTER_DRAWING_SECONDS = 0.05,
    ---The pause of the input after which a preview may start.
    QUIET_SECONDS = 0.15,
}

---@param now number
---@param shown_at number when the list or the panel showed
---@param last_input_at number|nil when the last input of the list or the panel came, or nil before
---any input
---@return number the seconds until the next preview may start, 0 when it may start now
function preview_pacing.seconds_until_next_preview(now, shown_at, last_input_at)
    local seconds = math.max(0, shown_at + preview_pacing.AFTER_DRAWING_SECONDS - now)
    if last_input_at then
        seconds = math.max(seconds, last_input_at + preview_pacing.QUIET_SECONDS - now)
    end
    return seconds
end

return preview_pacing
