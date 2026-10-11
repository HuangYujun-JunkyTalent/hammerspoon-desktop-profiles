---Reads the icons of applications and the blurred snapshots of windows for the list.
local window_previews = {}

---A snapshot is rendered this small and drawn larger, which blurs it.
local BLURRED_SIZE = { w = 24, h = 15 }

---@param bundle_id string
---@return table|nil an hs.image
function window_previews.read_app_icon(bundle_id)
    return hs.image.imageFromAppBundle(bundle_id)
end

---Takes a snapshot of the window and renders it small.
---@param window_id integer
---@return table|nil image an hs.image, or nil when macOS gives no snapshot
---@return number seconds the time the snapshot took
function window_previews.take_blurred_snapshot(window_id)
    local started_at = hs.timer.secondsSinceEpoch()
    local snapshot = hs.window.snapshotForID(window_id)
    local seconds = hs.timer.secondsSinceEpoch() - started_at
    if not snapshot then
        return nil, seconds
    end
    return snapshot:bitmapRepresentation(BLURRED_SIZE), seconds
end

return window_previews
