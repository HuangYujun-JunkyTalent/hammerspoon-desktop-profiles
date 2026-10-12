local tiling_position = require("window_tiling.core.tiling_position")

local tiling_controller = {}

---@class TilingController
---@field settings TilingSettings
---@field hotkeys table[] the hs.hotkey objects, kept so that Lua does not collect them
local TilingController = {}
TilingController.__index = TilingController

---@param message string
local function notify(message)
    hs.notify.new({ title = "Window tiling", informativeText = message }):send()
end

---The window that a tiling acts on: the focused window when it is a standard window, and otherwise
---the frontmost standard window.
---A launcher such as Asyar keeps the focus in its search panel, which is no standard window, while
---it opens the URL of a tiling.
---@return table|nil window an hs.window
local function find_window_to_tile()
    local focused = hs.window.focusedWindow()
    if focused and focused:isStandard() then
        return focused
    end
    for _, window in ipairs(hs.window.orderedWindows()) do
        if window:isStandard() then
            return window
        end
    end
    return nil
end

---Sets the frame without animation, as Rectangle does by default, and gives the window the focus,
---which a launcher took.
---@param position string a value of tiling_position
local function tile_front_window(position)
    local window = find_window_to_tile()
    if not window then
        notify("No standard window is in sight, so no window was tiled.")
        return
    end
    local screen = window:screen()
    if not screen then
        notify(string.format("The window %q is on no screen, so it was not tiled.", window:title()))
        return
    end
    window:setFrame(tiling_position.compute_frame(position, screen:frame()), 0)
    window:focus()
end

---@param params table<string, string>
local function run_url_command(params)
    local position, error_message = tiling_position.parse(params.position)
    if not position then
        notify(error_message)
        return
    end
    tile_front_window(position)
end

function TilingController:bind_hotkeys()
    for _, position in ipairs(tiling_position.POSITIONS) do
        local key = self.settings.key_by_position[position]
        if key then
            table.insert(
                self.hotkeys,
                hs.hotkey.bind(self.settings.hotkey_modifiers, key, function()
                    tile_front_window(position)
                end)
            )
        end
    end
end

---@param settings TilingSettings
---@return TilingController
function tiling_controller.start(settings)
    local controller = setmetatable({ settings = settings, hotkeys = {} }, TilingController)
    controller:bind_hotkeys()
    hs.urlevent.bind(settings.url_event_name, function(_, params)
        run_url_command(params)
    end)
    return controller
end

return tiling_controller
