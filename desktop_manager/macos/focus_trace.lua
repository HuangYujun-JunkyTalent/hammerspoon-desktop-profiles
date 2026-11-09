local read_desktops = require("desktop_manager.macos.read_desktops")

---The trace of the focus and the desktops, a debug mode that writes one line to a file for each
---activation of an application, each focus of a window, each change of the desktops and each mark
---that a press of the list or the search sets, so that a jump to the wrong desktop can be read
---afterwards.
---The trace runs until it is stopped or Hammerspoon reloads its configuration.
---While it is off, it keeps no watcher, no window filter and no timer, and a mark builds no text.
local focus_trace = {}

---A file beyond this size moves to the same name with ".1" after it when a trace starts.
local ROTATE_BYTES = 5 * 1024 * 1024

---The seconds after a focus of the list or the search at which the trace notes where the focus
---and the desktops have settled.
local SETTLE_CHECK_SECONDS = { 0.5, 1.5, 3 }

---@class RunningTrace
---@field path string
---@field file file*
---@field application_watcher table an hs.application.watcher
---@field space_watcher table an hs.spaces.watcher
---@field window_filter table an hs.window.filter
---@field timers table[] the hs.timer objects of the checks after a focus, kept from collection

---@type RunningTrace|nil
local running = nil

local EVENT_NAMES = nil

---@return table<integer, string> the names of the events of hs.application.watcher
local function read_event_names()
    if not EVENT_NAMES then
        local watcher = hs.application.watcher
        EVENT_NAMES = {
            [watcher.activated] = "activated",
            [watcher.deactivated] = "deactivated",
            [watcher.launched] = "launched",
            [watcher.launching] = "launching",
            [watcher.terminated] = "terminated",
            [watcher.hidden] = "hidden",
            [watcher.unhidden] = "unhidden",
        }
    end
    return EVENT_NAMES
end

---@return string such as "Built-in Retina Display 2/7 (519)", one part per screen, with the
---desktop that shows, the number of desktops and the space id of the desktop that shows
local function describe_desktops()
    local is_read, layout = pcall(read_desktops.read_desktop_layout)
    if not is_read then
        return "desktops unreadable: " .. tostring(layout)
    end
    local parts = {}
    for _, screen in ipairs(layout.screens) do
        local found = hs.screen.find(screen.screen_uuid)
        local number = "?"
        for index, space_id in ipairs(screen.space_ids) do
            if space_id == screen.active_space_id then
                number = tostring(index)
            end
        end
        table.insert(
            parts,
            string.format(
                "%s %s/%d (%s)",
                found and found:name() or screen.screen_uuid,
                number,
                #screen.space_ids,
                tostring(screen.active_space_id)
            )
        )
    end
    return table.concat(parts, ", ")
end

---@return string such as 'front Code, window 66006 "tac.tex — co-design-games"'
local function describe_front()
    local application = hs.application.frontmostApplication()
    local window = hs.window.focusedWindow()
    local window_text = window and string.format(" window %d %q", window:id(), window:title() or "")
        or ", no focused window"
    return string.format("front %s%s", application and application:name() or "none", window_text)
end

---@param event string
local function write_line(event)
    if not running then
        return
    end
    local now = hs.timer.secondsSinceEpoch()
    local line = string.format(
        "%s.%03d  %-60s | %s | %s\n",
        os.date("%Y-%m-%d %H:%M:%S", math.floor(now)),
        math.floor((now % 1) * 1000),
        event,
        describe_desktops(),
        describe_front()
    )
    running.file:write(line)
    running.file:flush()
end

---@param path string
local function rotate_when_large(path)
    local file = io.open(path, "r")
    if not file then
        return
    end
    local size = file:seek("end")
    file:close()
    if size and size > ROTATE_BYTES then
        os.rename(path, path .. ".1")
    end
end

---@return boolean whether the trace runs
function focus_trace.is_running()
    return running ~= nil
end

---Starts the trace into the file at the path, after the lines of earlier traces.
---@param path string
---@return string|nil error_message when the file cannot be opened
function focus_trace.start(path)
    if running then
        return nil
    end
    rotate_when_large(path)
    local file, error_message = io.open(path, "a")
    if not file then
        return error_message
    end
    local event_names = read_event_names()
    running = {
        path = path,
        file = file,
        timers = {},
        application_watcher = hs.application.watcher.new(function(name, event, application)
            local pid = application and application:pid()
            local bundle_id = application and application:bundleID()
            write_line(
                string.format(
                    "app %s %s pid=%s %s",
                    event_names[event] or tostring(event),
                    tostring(name),
                    tostring(pid),
                    tostring(bundle_id)
                )
            )
        end),
        space_watcher = hs.spaces.watcher.new(function()
            write_line("desktop changed")
        end),
        window_filter = hs.window.filter.new(true),
    }
    running.application_watcher:start()
    running.space_watcher:start()
    running.window_filter:subscribe(hs.window.filter.windowFocused, function(window, app_name)
        write_line(
            string.format(
                "window focused %s %s",
                tostring(app_name),
                tostring(window and window:id())
            )
        )
    end)
    write_line("trace started")
    return nil
end

---Stops the trace and closes its file.
function focus_trace.stop()
    if not running then
        return
    end
    write_line("trace stopped")
    running.application_watcher:stop()
    running.space_watcher:stop()
    running.window_filter:unsubscribeAll()
    running.window_filter:pause()
    for _, timer in ipairs(running.timers) do
        timer:stop()
    end
    running.file:close()
    running = nil
end

---Writes a line for a step of the desktop manager, while the trace runs.
---The text is built only then, so that a mark costs nothing while the trace is off.
---@param describe fun(): string the text of the line
function focus_trace.mark(describe)
    if running then
        write_line("mark: " .. describe())
    end
end

---Writes the mark, and notes where the focus and the desktops are a few times after it, while the
---trace runs.
---@param describe fun(): string the text of the line
function focus_trace.mark_and_watch(describe)
    if not running then
        return
    end
    local text = describe()
    write_line("mark: " .. text)
    for _, seconds in ipairs(SETTLE_CHECK_SECONDS) do
        table.insert(
            running.timers,
            hs.timer.doAfter(seconds, function()
                write_line(string.format("settled? %g seconds after: %s", seconds, text))
            end)
        )
    end
    while #running.timers > 30 do
        table.remove(running.timers, 1)
    end
end

return focus_trace
