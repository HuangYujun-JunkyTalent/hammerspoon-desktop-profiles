local javascript_tasks = require("desktop_manager.macos.javascript_tasks")
local preview_helper_output = require("desktop_manager.core.preview_helper_output")
local preview_method = require("desktop_manager.core.preview_method")
local preview_pacing = require("desktop_manager.core.preview_pacing")
local retained_timers = require("desktop_manager.macos.retained_timers")

---Reads the icons of applications, and the blurred previews of windows that the helper process
---`capture_window_previews.js` takes, for the list and the search.
local window_previews = {}

---How the previews of a list load: the box of the helper, the time limit of a capture, when the
---list showed, and the calls that the loading makes.
---@class PreviewLoading
---@field box table the w and h in pixels into which the helper scales each capture
---@field time_limit_seconds number
---@field shown_at number when the list showed, in seconds since the epoch
---@field is_wanted fun(): boolean whether the list still shows and the previews may load
---@field on_image fun(window_id: integer, image: table) receives each preview that macOS gives
---@field on_preview_taken fun(window_id: integer, blocking_seconds: number)|nil receives the time
---that the decoding of each preview held Hammerspoon
---@field on_too_slow fun(seconds: number) receives the time of a capture over the limit, which
---stops the previews until a reload
---@field on_failed fun(reason: string) receives why the helper failed, which ends the loading of
---the list

---What a list asks of the loader of the previews.
---@class PreviewRequest
---@field preview_size table the w and h of a preview in points
---@field shown_at number when the list showed, in seconds since the epoch
---@field is_wanted fun(): boolean whether the list still shows
---@field on_image fun(window_id: integer, image: table) receives each preview as it comes
---@field on_preview_taken fun(window_id: integer, blocking_seconds: number)|nil receives the time
---that the decoding of each preview held Hammerspoon

---A Retina display shows a point with two pixels in each direction.
local PIXELS_PER_POINT = 2
local HELPER_SCRIPT_NAME = "capture_window_previews.js"
---The time that the start of `osascript -l JavaScript` may take, beyond the time limit of a
---capture, before a helper that gave no output counts as failed.
local HELPER_START_SECONDS = 1

---@param preview_size table the w and h of a preview in points
---@param blur number 1 for full detail, 2 for half, 4 for a quarter
---@return table the w and h in pixels into which the helper scales each capture, which blurs it
---when the list draws it at the size of a preview
local function measure_box(preview_size, blur)
    return {
        w = preview_size.w * PIXELS_PER_POINT / blur,
        h = preview_size.h * PIXELS_PER_POINT / blur,
    }
end

---@param box table
---@param window_ids integer[]
---@return string[] the arguments of the helper: the box and the windows
local function list_helper_arguments(box, window_ids)
    local arguments = { string.format("%.2f", box.w), string.format("%.2f", box.h) }
    for _, window_id in ipairs(window_ids) do
        table.insert(arguments, tostring(window_id))
    end
    return arguments
end

---One run of the helper on a batch of windows.
---@class PreviewHelper
---@field task table|nil the hs.task
---@field rest string the start of a line whose end has not come yet
---@field silence_timer table|nil the hs.timer that gives the helper up when no output comes
---@field has_exited boolean

---The windows of a list whose previews the helper takes, in batches.
---The queue starts one helper with the windows that wait once the list has drawn, and the windows
---that the list adds while the helper runs wait for the next helper, which starts when that one
---ends.
---@class PreviewQueue
---@field loading PreviewLoading
---@field waiting_window_ids integer[] the windows that wait for the next helper
---@field start_timer table|nil the hs.timer that starts the next helper once the list has drawn
---@field helper PreviewHelper|nil the helper that runs
---@field is_stopped boolean whether the list closed or a helper failed, which ends the loading, so
---that the later output and the exit of the helper count for nothing
local PreviewQueue = {}
PreviewQueue.__index = PreviewQueue

---Sets the timer that starts the next helper, unless a helper runs or waits for its start, no
---window waits, or the list no longer wants the previews.
function PreviewQueue:schedule()
    if
        self.is_stopped
        or self.helper
        or self.start_timer
        or #self.waiting_window_ids == 0
        or not self.loading.is_wanted()
    then
        return
    end
    local seconds = preview_pacing.seconds_until_previews_start(
        hs.timer.secondsSinceEpoch(),
        self.loading.shown_at
    )
    self.start_timer = retained_timers.after(seconds, function()
        self.start_timer = nil
        self:start_helper()
    end)
end

---Stops the loading: no helper starts any more, and the helper that runs ends.
function PreviewQueue:stop()
    self.is_stopped = true
    retained_timers.stop(self.start_timer)
    self.start_timer = nil
    local helper = self.helper
    self.helper = nil
    if helper then
        retained_timers.stop(helper.silence_timer)
        helper.silence_timer = nil
        if helper.task and helper.task:isRunning() then
            helper.task:terminate()
        end
    end
end

---Stops the loading and says why in the console, while the windows without a preview keep their
---icons.
---@param reason string
function PreviewQueue:give_up(reason)
    self:stop()
    self.loading.on_failed(reason)
end

---Gives the helper up when no output comes within the time limit of a capture and the start of
---`osascript`.
---@param helper PreviewHelper
function PreviewQueue:watch_helper(helper)
    retained_timers.stop(helper.silence_timer)
    local seconds = self.loading.time_limit_seconds + HELPER_START_SECONDS
    helper.silence_timer = retained_timers.after(seconds, function()
        helper.silence_timer = nil
        self:give_up(
            string.format("the helper of the previews gave nothing for %.1f seconds", seconds)
        )
    end)
end

---Shows the preview of one line of the helper, and stops the previews until a reload when its
---capture took longer than the time limit.
---@param line string
function PreviewQueue:show_helper_line(line)
    local loading = self.loading
    local helper_line = preview_helper_output.parse_line(line)
    if not helper_line then
        self:give_up("the helper of the previews gave a line that names no window and no image")
        return
    end
    if helper_line.capture_seconds > loading.time_limit_seconds then
        self:stop()
        loading.on_too_slow(helper_line.capture_seconds)
        return
    end
    if not helper_line.data_url then
        return
    end
    local started_at = hs.timer.secondsSinceEpoch()
    local image = hs.image.imageFromURL(helper_line.data_url)
    if image then
        loading.on_image(helper_line.window_id, image)
    end
    if loading.on_preview_taken then
        loading.on_preview_taken(helper_line.window_id, hs.timer.secondsSinceEpoch() - started_at)
    end
end

---Shows the previews of the lines that the output completes.
---Hammerspoon may give the last output of a helper after its exit.
---@param helper PreviewHelper
---@param output string|nil
function PreviewQueue:read_helper_output(helper, output)
    if self.is_stopped or not output or output == "" then
        return
    end
    if not helper.has_exited then
        self:watch_helper(helper)
    end
    local lines
    lines, helper.rest = preview_helper_output.split_lines(helper.rest, output)
    for _, line in ipairs(lines) do
        self:show_helper_line(line)
        if self.is_stopped then
            return
        end
    end
end

---Takes the exit of a helper, and starts the next helper for the windows that wait.
---@param helper PreviewHelper
---@param exit_code integer
---@param output string|nil the output that the streaming callback has not received
function PreviewQueue:end_helper(helper, exit_code, output)
    helper.has_exited = true
    retained_timers.stop(helper.silence_timer)
    helper.silence_timer = nil
    self:read_helper_output(helper, output)
    if self.is_stopped then
        return
    end
    if exit_code ~= 0 then
        self:give_up(string.format("the helper of the previews ended with status %d", exit_code))
        return
    end
    self.helper = nil
    self:schedule()
end

---Starts a helper with the windows that wait.
function PreviewQueue:start_helper()
    local window_ids = self.waiting_window_ids
    self.waiting_window_ids = {}
    local helper = { rest = "", has_exited = false }
    self.helper = helper
    helper.task = javascript_tasks.new(
        HELPER_SCRIPT_NAME,
        list_helper_arguments(self.loading.box, window_ids),
        function(exit_code, output)
            self:end_helper(helper, exit_code, output)
        end,
        function(_, output)
            self:read_helper_output(helper, output)
            return true
        end
    )
    if not helper.task or not helper.task:start() then
        self:give_up("the helper of the previews did not start")
        return
    end
    self:watch_helper(helper)
end

---Puts the windows at the end of the queue, as when a new list of the window server adds windows.
---@param window_ids integer[]
function PreviewQueue:add(window_ids)
    if self.is_stopped then
        return
    end
    for _, window_id in ipairs(window_ids) do
        table.insert(self.waiting_window_ids, window_id)
    end
    self:schedule()
end

---Loads the previews of the list and the search under the setting for snapshots, and stops the
---previews until the next reload once a capture is slower than the time limit, because the
---function behind it once blocked Hammerspoon for two minutes on macOS 27.0.1.
---Keeps the icon of each application that the list and the search showed, until the application
---quits, so that an opening reads only the icons of the applications new to it.
---Each controller holds one loader, so that a stop holds until the next start of the controller.
---@class PreviewLoader
---@field settings Settings
---@field log table an hs.logger
---@field are_snapshots_stopped boolean whether a slow capture stopped the previews until a reload
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

---Takes the previews of the windows of a list through the helper, after the list shows, and gives
---each to `on_image` as it comes, under the setting for snapshots.
---@param window_ids integer[]
---@param request PreviewRequest
---@return PreviewQueue the queue that takes the windows that the list adds later, and that the list
---stops when it closes
function PreviewLoader:load(window_ids, request)
    local queue = setmetatable({ waiting_window_ids = {}, is_stopped = false }, PreviewQueue)
    queue.loading = {
        box = measure_box(request.preview_size, self.settings.preview_blur),
        time_limit_seconds = self.settings.timing.snapshot_time_limit_seconds,
        shown_at = request.shown_at,
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
        on_failed = function(reason)
            self.log.w(reason .. ", so the windows without a preview show their icons")
        end,
    }
    queue:add(window_ids)
    return queue
end

return window_previews
