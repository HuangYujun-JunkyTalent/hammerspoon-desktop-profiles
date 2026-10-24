local preview_method = require("desktop_manager.core.preview_method")
local preview_pacing = require("desktop_manager.core.preview_pacing")
local retained_timers = require("desktop_manager.macos.retained_timers")

---Reads the icons of applications and the blurred snapshots of windows for the list.
local window_previews = {}

---How the previews of a list load: their blur, their size, the time limit of a snapshot, the
---times that pace the snapshots, and the calls that the loading makes.
---@class PreviewLoading
---@field blur number the setting preview_blur
---@field preview_size table the w and h of a preview in points
---@field time_limit_seconds number
---@field shown_at number when the list showed, in seconds since the epoch
---@field read_last_input_at fun(): number|nil when the last key, press, click or hover of the list
---came, or nil before any
---@field is_wanted fun(): boolean whether the list still shows and the snapshots may run
---@field on_image fun(window_id: integer, image: table) receives each snapshot that macOS gives
---@field on_preview_taken fun(window_id: integer, blocking_seconds: number)|nil receives the time
---that each snapshot and its rendering held Hammerspoon
---@field on_too_slow fun(seconds: number) receives the time of a snapshot over the limit, which
---ends the loading

---What a list asks of the loader of the previews.
---@class PreviewRequest
---@field preview_size table the w and h of a preview in points
---@field shown_at number when the list showed, in seconds since the epoch
---@field read_last_input_at fun(): number|nil when the last key, press, click or hover of the list
---came, or nil before any
---@field is_wanted fun(): boolean whether the list still shows
---@field on_image fun(window_id: integer, image: table) receives each preview as it comes
---@field on_preview_taken fun(window_id: integer, blocking_seconds: number)|nil receives the time
---that each snapshot and its rendering held Hammerspoon

---A Retina display shows a point with two pixels in each direction.
local PIXELS_PER_POINT = 2

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

---The snapshots of the windows of a list, which the queue takes one at a time, after the list has
---drawn and while its input pauses, as `preview_pacing` says, so that the list shows at once and
---its previews come as they are taken.
---@class PreviewQueue
---@field loading PreviewLoading
---@field window_ids integer[] the windows in the order of their snapshots
---@field taken_count integer the windows whose snapshots the queue has taken
---@field timer table|nil the one hs.timer of the queue, while a snapshot waits for its time
local PreviewQueue = {}
PreviewQueue.__index = PreviewQueue

---@param queue PreviewQueue
---@return number the seconds until the next snapshot may start
local function read_seconds_until_next_snapshot(queue)
    return preview_pacing.seconds_until_next_preview(
        hs.timer.secondsSinceEpoch(),
        queue.loading.shown_at,
        queue.loading.read_last_input_at()
    )
end

---Sets the timer of the next snapshot, unless one is set, no snapshot waits or the list no longer
---wants the snapshots.
function PreviewQueue:schedule()
    if self.timer or self.taken_count >= #self.window_ids or not self.loading.is_wanted() then
        return
    end
    self.timer = retained_timers.after(read_seconds_until_next_snapshot(self), function()
        self.timer = nil
        self:take_next_snapshot()
    end)
end

---Takes the next snapshot when its time has come, as an input may have come since the timer was
---set, and sets the timer of the snapshot after it.
function PreviewQueue:take_next_snapshot()
    if not self.loading.is_wanted() then
        return
    end
    if read_seconds_until_next_snapshot(self) > 0 then
        self:schedule()
        return
    end
    self.taken_count = self.taken_count + 1
    local window_id = self.window_ids[self.taken_count]
    local loading = self.loading
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
    self:schedule()
end

---Puts the windows at the end of the queue, as when a new list of the window server adds windows.
---@param window_ids integer[]
function PreviewQueue:add(window_ids)
    for _, window_id in ipairs(window_ids) do
        table.insert(self.window_ids, window_id)
    end
    self:schedule()
end

---Loads the previews of the list and the search under the setting for snapshots, and stops the
---snapshots until the next reload once a snapshot is slower than the time limit, because the
---function behind it once blocked Hammerspoon for two minutes on macOS 27.0.1.
---Keeps the icon of each application that the list and the search showed, until the application
---quits, so that an opening reads only the icons of the applications new to it.
---Each controller holds one loader, so that a stop holds until the next start of the controller.
---@class PreviewLoader
---@field settings Settings
---@field log table an hs.logger
---@field are_snapshots_stopped boolean whether a slow snapshot stopped the snapshots until a reload
---@field app_icons table<string, table|false> the hs.image of the icon of each bundle id read, or
---false for a bundle id without an icon
local PreviewLoader = {}
PreviewLoader.__index = PreviewLoader

---@param settings Settings
---@param log table an hs.logger
---@return PreviewLoader
function window_previews.new_loader(settings, log)
    return setmetatable(
        { settings = settings, log = log, are_snapshots_stopped = false, app_icons = {} },
        PreviewLoader
    )
end

---@param bundle_id string
---@return table|nil the hs.image of the icon of the application, read once until it quits
function PreviewLoader:read_app_icon(bundle_id)
    if self.app_icons[bundle_id] == nil then
        self.app_icons[bundle_id] = hs.image.imageFromAppBundle(bundle_id) or false
    end
    return self.app_icons[bundle_id] or nil
end

---Forgets the icon of an application that quit, so that an update of the application shows its
---new icon once it runs again.
---@param bundle_id string
function PreviewLoader:forget_app_icon(bundle_id)
    self.app_icons[bundle_id] = nil
end

---Takes the snapshots of the windows of a list one at a time, after the list shows, and gives each
---to `on_image` as it comes, under the setting for snapshots.
---@param window_ids integer[]
---@param request PreviewRequest
---@return PreviewQueue the queue that takes the windows that the list adds later
function PreviewLoader:load(window_ids, request)
    local queue = setmetatable({ window_ids = {}, taken_count = 0 }, PreviewQueue)
    queue.loading = {
        blur = self.settings.preview_blur,
        preview_size = request.preview_size,
        time_limit_seconds = self.settings.timing.snapshot_time_limit_seconds,
        shown_at = request.shown_at,
        read_last_input_at = request.read_last_input_at,
        is_wanted = function()
            return self.settings.preview_method == preview_method.BLURRED_SNAPSHOTS
                and request.is_wanted()
                and not self.are_snapshots_stopped
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
    }
    queue:add(window_ids)
    return queue
end

return window_previews
