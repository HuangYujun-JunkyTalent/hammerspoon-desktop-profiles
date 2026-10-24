---When the helper that takes the previews of the list or the search may start.
---The helper starts after the list or the panel has had the time to draw, because the start of its
---process holds the main thread of Hammerspoon for a few milliseconds.
local preview_pacing = {
    ---A timer due this long after the panel shows lets the run loop of Hammerspoon draw the panel
    ---first, because a timer of 0 seconds may fire before the drawing, and one frame at 60 Hz takes
    ---about 0.017 seconds.
    AFTER_DRAWING_SECONDS = 0.05,
}

---@param now number
---@param shown_at number when the list or the panel showed
---@return number the seconds until the helper of the previews may start, 0 when it may start now
function preview_pacing.seconds_until_previews_start(now, shown_at)
    return math.max(0, shown_at + preview_pacing.AFTER_DRAWING_SECONDS - now)
end

return preview_pacing
