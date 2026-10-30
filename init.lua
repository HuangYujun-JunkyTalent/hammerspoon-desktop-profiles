-- Hammerspoon runs this file through the line `dofile("<repository>/init.lua")` in
-- ~/.hammerspoon/init.lua, which `make install-loader` writes.
local repository_folder = debug.getinfo(1, "S").source:match("^@(.*)/init%.lua$")
if not repository_folder then
    error("init.lua must be loaded from its file with dofile, so that it finds its repository")
end
package.path = string.format("%s/?.lua;%s", repository_folder, package.path)

require("hs.ipc")

local default_settings = require("desktop_manager.default_settings")
local profile_controller = require("desktop_manager.macos.profile_controller")
local shortcut_center = require("keyboard_shortcuts.macos.shortcut_center")
local tiling_controller = require("window_tiling.macos.tiling_controller")
local tiling_settings = require("window_tiling.default_settings")
local trash_controller = require("trash.macos.trash_controller")
local trash_settings = require("trash.default_settings")

-- The globals keep the hotkeys and watchers of the desktop manager and the window tiling from being
-- garbage-collected, and let the command-line tool reach the controllers, as in
-- `hs -c "desktop_manager:print_diagnostics()"`.
-- One center binds the shortcuts of the desktop manager and the window tiling, from the overrides
-- that the window "Keyboard shortcuts…" of the menu bar item writes.
-- The trash tool keeps its controller alive through the callback that `hs.urlevent` holds, and
-- binds no hotkey, so it sets no global.
local shortcuts = shortcut_center.new(hs.configdir .. "/keyboard-shortcuts.json")
desktop_manager = profile_controller.start(
    default_settings.create(hs.configdir .. "/desktop-manager-state.json"),
    shortcuts
)
window_tiler = tiling_controller.start(tiling_settings.create(), shortcuts)
trash_controller.start(trash_settings.create())
shortcuts:check_overrides()
