local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local tiling_controller = require("window_tiling.macos.tiling_controller")
local default_settings = require("window_tiling.default_settings")

local BUILTIN_FRAME = { x = 0, y = 25, w = 1440, h = 875 }
local EXTERNAL_FRAME = { x = 1440, y = 0, w = 2560, h = 1415 }
local EDITOR_WINDOW_ID = 7
local URL_EVENT_NAME = "window-tiling"

---@param window_frame Rect
---@return table world
local function start_with_focused_window(window_frame)
    local world = fake_hammerspoon.install({
        screens = {
            { id = 1, uuid = "BUILTIN", name = "Built-in Retina Display", frame = BUILTIN_FRAME },
            { id = 2, uuid = "EXTERNAL", name = "DELL U2720Q", frame = EXTERNAL_FRAME },
        },
        displays = {
            { uuid = "BUILTIN", space_ids = { 1 }, active_space_id = 1 },
            { uuid = "EXTERNAL", space_ids = { 2 }, active_space_id = 2 },
        },
        applications = {
            { bundle_id = "com.microsoft.VSCode", name = "Code", is_running = true },
        },
        windows = {
            {
                id = EDITOR_WINDOW_ID,
                bundle_id = "com.microsoft.VSCode",
                title = "README.md",
                space_id = 1,
                frame = window_frame,
            },
        },
    })
    world.focused_window_id = EDITOR_WINDOW_ID
    tiling_controller.start(default_settings.create())
    return world
end

return {
    control_option_left_puts_the_focused_window_on_the_left_half = function()
        local world = start_with_focused_window({ x = 300, y = 200, w = 600, h = 400 })
        world.hotkey_by_shortcut["ctrl+alt left"]()
        expect.equal(world.windows[EDITOR_WINDOW_ID].frame, { x = 0, y = 25, w = 720, h = 875 })
    end,

    control_option_return_fills_the_screen_of_the_window = function()
        local world = start_with_focused_window({ x = 2000, y = 300, w = 800, h = 600 })
        world.hotkey_by_shortcut["ctrl+alt return"]()
        expect.equal(world.windows[EDITOR_WINDOW_ID].frame, EXTERNAL_FRAME)
    end,

    a_url_tiles_the_focused_window = function()
        local world = start_with_focused_window({ x = 300, y = 200, w = 600, h = 400 })
        world.url_handlers[URL_EVENT_NAME](URL_EVENT_NAME, { position = "bottom-half" })
        expect.equal(world.windows[EDITOR_WINDOW_ID].frame, { x = 0, y = 463, w = 1440, h = 437 })
    end,

    a_url_with_an_unknown_position_notifies_and_moves_nothing = function()
        local frame = { x = 300, y = 200, w = 600, h = 400 }
        local world = start_with_focused_window(frame)
        world.url_handlers[URL_EVENT_NAME](URL_EVENT_NAME, { position = "center" })
        expect.equal(world.windows[EDITOR_WINDOW_ID].frame, frame)
        expect.equal(#world.notifications, 1)
    end,

    without_a_focused_window_a_shortcut_notifies = function()
        local world = start_with_focused_window({ x = 300, y = 200, w = 600, h = 400 })
        world.focused_window_id = nil
        world.hotkey_by_shortcut["ctrl+alt up"]()
        expect.equal(world.notifications, { "No window has the focus, so no window was tiled." })
    end,
}
