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

-- The global keeps the hotkeys and watchers from being garbage-collected,
-- and lets the command-line tool reach the controller, as in
-- `hs -c "desktop_manager:print_diagnostics()"`.
desktop_manager =
    profile_controller.start(default_settings.create(hs.configdir .. "/desktop-manager-state.json"))
