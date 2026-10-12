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
local tiling_controller = require("window_tiling.macos.tiling_controller")
local tiling_settings = require("window_tiling.default_settings")

-- The globals keep the hotkeys and watchers of the two tools from being garbage-collected,
-- and let the command-line tool reach the controllers, as in
-- `hs -c "desktop_manager:print_diagnostics()"`.
desktop_manager =
    profile_controller.start(default_settings.create(hs.configdir .. "/desktop-manager-state.json"))
window_tiler = tiling_controller.start(tiling_settings.create())
