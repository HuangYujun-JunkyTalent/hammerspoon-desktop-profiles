local preview_method = require("desktop_manager.core.preview_method")
local retained_timers = require("desktop_manager.macos.retained_timers")

---Reads the icons of applications and the blurred snapshots of windows for the list.
local window_previews = {}

---How the previews of a list load: their blur, their size, the time limit of a snapshot, and the
---calls that the loading makes.
---@class PreviewLoading
---@field blur number the setting preview_blur
---@field preview_size table the w and h of a preview in points
---@field time_limit_seconds number
---@field is_wanted fun(): boolean whether the list still shows and the snapshots may run
---@field on_image fun(window_id: integer, image: table) receives each snapshot that macOS gives
---@field on_preview_taken fun(window_id: integer, blocking_seconds: number)|nil receives the time
---that each snapshot and its rendering held Hammerspoon
---@field on_too_slow fun(seconds: number) receives the time of a snapshot over the limit, which
---ends the loading

---What a list asks of the loader of the previews.
---@class PreviewRequest
---@field preview_size table the w and h of a preview in points
---@field is_wanted fun(): boolean whether the list still shows
---@field on_image fun(window_id: integer, image: table) receives each preview as it comes
---@field on_preview_taken fun(window_id: integer, blocking_seconds: number)|nil receives the time
---that each snapshot and its rendering held Hammerspoon

---A Retina display shows a point with two pixels in each direction.
local PIXELS_PER_POINT = 2

---@param bundle_id string
---@return table|nil an hs.image
function window_previews.read_app_icon(bundle_id)
    return hs.image.imageFromAppBundle(bundle_id)
end

---The size that fits the snapshot, with its proportions, into the pixels of the preview divided by
---the blur.
---@param snapshot_size table the w and h of the snapshot
---@param blur number 1 for full detail, 2 for half, 4 for a quarter
---@param preview_size table the w and h of a preview in points
---@return table the w and h of the rendering
local function fit_rendering(snapshot_size, blur, preview_size)
    local scale = math.min(
        preview_size.w * PIXELS_PER_POINT / blur / snapshot_size.w,
        preview_size.h * PIXELS_PER_POINT / blur / snapshot_size.h
    )
    return {
        w = math.max(1, math.floor(snapshot_size.w * scale + 0.5)),
        h = math.max(1, math.floor(snapshot_size.h * scale + 0.5)),
    }
end

---Takes a snapshot of the window and renders it small, which blurs it when the list draws it at
---the size of a preview.
---@param window_id integer
---@param blur number the setting preview_blur, 1 or more
---@param preview_size table the setting preview_size, in points
---@return table|nil image an hs.image, or nil when macOS gives no snapshot
---@return number snapshot_seconds the time the snapshot took, without its rendering
local function take_blurred_snapshot(window_id, blur, preview_size)
    local started_at = hs.timer.secondsSinceEpoch()
    local snapshot = hs.window.snapshotForID(window_id)
    local snapshot_seconds = hs.timer.secondsSinceEpoch() - started_at
    if not snapshot then
        return nil, snapshot_seconds
    end
    return snapshot:bitmapRepresentation(fit_rendering(snapshot:size(), blur, preview_size)),
        snapshot_seconds
end

---Takes the snapshots of the windows one at a time, each after Hammerspoon has handled its other
---events, so the list shows at once and its previews come as they are taken.
---@param window_ids integer[]
---@param loading PreviewLoading
function window_previews.load_one_at_a_time(window_ids, loading)
    local index = 0
    local function take_next_snapshot()
        index = index + 1
        local window_id = window_ids[index]
        if not window_id or not loading.is_wanted() then
            return
        end
        local started_at = hs.timer.secondsSinceEpoch()
        local image, snapshot_seconds =
            take_blurred_snapshot(window_id, loading.blur, loading.preview_size)
        if loading.on_preview_taken then
            loading.on_preview_taken(window_id, hs.timer.secondsSinceEpoch() - started_at)
        end
        if snapshot_seconds > loading.time_limit_seconds then
            loading.on_too_slow(snapshot_seconds)
            return
        end
        if image then
            loading.on_image(window_id, image)
        end
        retained_timers.defer(take_next_snapshot)
    end
    retained_timers.defer(take_next_snapshot)
end

---Loads the previews of the list and the search under the setting for snapshots, and stops the
---snapshots until the next reload once a snapshot is slower than the time limit, because the
---function behind it once blocked Hammerspoon for two minutes on macOS 27.0.1.
---Each controller holds one loader, so that a stop holds until the next start of the controller.
---@class PreviewLoader
---@field settings Settings
---@field log table an hs.logger
---@field are_snapshots_stopped boolean whether a slow snapshot stopped the snapshots until a reload
local PreviewLoader = {}
PreviewLoader.__index = PreviewLoader

---@param settings Settings
---@param log table an hs.logger
---@return PreviewLoader
function window_previews.new_loader(settings, log)
    return setmetatable(
        { settings = settings, log = log, are_snapshots_stopped = false },
        PreviewLoader
    )
end

---Takes the snapshots of the windows of a list one at a time, after the list shows, and gives each
---to `on_image` as it comes, under the setting for snapshots.
---@param window_ids integer[]
---@param request PreviewRequest
function PreviewLoader:load(window_ids, request)
    if self.settings.preview_method ~= preview_method.BLURRED_SNAPSHOTS then
        return
    end
    window_previews.load_one_at_a_time(window_ids, {
        blur = self.settings.preview_blur,
        preview_size = request.preview_size,
        time_limit_seconds = self.settings.timing.snapshot_time_limit_seconds,
        is_wanted = function()
            return request.is_wanted() and not self.are_snapshots_stopped
        end,
        on_image = request.on_image,
        on_preview_taken = request.on_preview_taken,
        on_too_slow = function(seconds)
            self.are_snapshots_stopped = true
            self.log.w(
                string.format(
                    "a snapshot took %.1f seconds, so the list shows icons until the next reload",
                    seconds
                )
            )
        end,
    })
end

return window_previews
