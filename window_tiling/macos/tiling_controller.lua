local shortcut_center = require("keyboard_shortcuts.macos.shortcut_center")
local tiling_position = require("window_tiling.core.tiling_position")

local tiling_controller = {}

---@class TilingController
---@field shortcuts ShortcutCenter
---@field log table an hs.logger, whose lines show in the Hammerspoon console
local TilingController = {}
TilingController.__index = TilingController

---@param message string
function TilingController:notify(message)
    self.log.w(message)
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
function TilingController:tile_front_window(position)
    local window = find_window_to_tile()
    if not window then
        self:notify("No standard window is in sight, so no window was tiled.")
        return
    end
    local screen = window:screen()
    if not screen then
        self:notify(
            string.format("The window %q is on no screen, so it was not tiled.", window:title())
        )
        return
    end
    local frame = tiling_position.compute_frame(position, screen:frame())
    self.log.i(string.format("%s: %s, %q", position, window:application():name(), window:title()))
    window:setFrame(frame, 0)
    window:focus()
end

---@param params table<string, string>
function TilingController:run_url_command(params)
    local position, error_message = tiling_position.parse(params.position)
    if not position then
        self:notify(error_message)
        return
    end
    self:tile_front_window(position)
end

---The tiling actions, with the default shortcuts of Rectangle: Control-Option with Return or an
---arrow.
---@return RegisteredAction[]
function TilingController:list_shortcut_actions()
    local actions = {}
    for _, description in ipairs(tiling_position.DESCRIPTIONS) do
        table.insert(actions, {
            id = "tiling." .. description.position,
            group = "Window tiling",
            title = description.title,
            default = { modifiers = { "ctrl", "alt" }, key = description.default_key },
            on_press = function()
                self:tile_front_window(description.position)
            end,
        })
    end
    return actions
end

---@param settings TilingSettings
---@param shortcuts ShortcutCenter|nil the center of the shortcuts of every tool, or nil for a
---center of this tool alone
---@return TilingController
function tiling_controller.start(settings, shortcuts)
    local controller = setmetatable({
        shortcuts = shortcuts or shortcut_center.new(nil),
        log = hs.logger.new("win_tiling", "info"),
    }, TilingController)
    controller.shortcuts:register(controller:list_shortcut_actions())
    hs.urlevent.bind(settings.url_event_name, function(_, params)
        controller:run_url_command(params)
    end)
    return controller
end

return tiling_controller
