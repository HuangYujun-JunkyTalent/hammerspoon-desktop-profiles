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

---Sets the frame without animation, as Rectangle does by default.
---@param position string a value of tiling_position
local function tile_focused_window(position)
    local window = hs.window.focusedWindow()
    if not window then
        notify("No window has the focus, so no window was tiled.")
        return
    end
    local screen = window:screen()
    if not screen then
        notify(string.format("The window %q is on no screen, so it was not tiled.", window:title()))
        return
    end
    window:setFrame(tiling_position.compute_frame(position, screen:frame()), 0)
end

---@param params table<string, string>
local function run_url_command(params)
    local position, error_message = tiling_position.parse(params.position)
    if not position then
        notify(error_message)
        return
    end
    tile_focused_window(position)
end

function TilingController:bind_hotkeys()
    for _, position in ipairs(tiling_position.POSITIONS) do
        local key = self.settings.key_by_position[position]
        if key then
            table.insert(
                self.hotkeys,
                hs.hotkey.bind(self.settings.hotkey_modifiers, key, function()
                    tile_focused_window(position)
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
