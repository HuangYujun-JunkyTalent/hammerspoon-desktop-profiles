---Fixtures that several test files share: the built-in display and the Dell monitor of the fake,
---the displays of those two screens, the default settings, and the desktops of one screen.
---Each builder returns new tables, because a case may change a screen or a display of its world.
local default_settings = require("desktop_manager.default_settings")

local fake_worlds = {}

---@return table screen the built-in display, as `fake_hammerspoon.install` takes a screen
function fake_worlds.build_builtin_screen()
    return {
        id = 1,
        uuid = "BUILTIN-UUID",
        name = "Built-in Retina Display",
        frame = { x = 0, y = 25, w = 1440, h = 875 },
    }
end

---@return table screen the Dell monitor to the right of the built-in display
function fake_worlds.build_dell_screen()
    return {
        id = 2,
        uuid = "DELL-UUID",
        name = "DELL S2725DS",
        frame = { x = 1440, y = 0, w = 2560, h = 1415 },
    }
end

---The displays of the built-in display and the Dell monitor, each showing its first desktop.
---@param builtin_space_ids integer[]
---@param dell_space_ids integer[]
---@return table[] displays
function fake_worlds.build_two_displays(builtin_space_ids, dell_space_ids)
    return {
        {
            uuid = "BUILTIN-UUID",
            space_ids = builtin_space_ids,
            active_space_id = builtin_space_ids[1],
        },
        {
            uuid = "DELL-UUID",
            space_ids = dell_space_ids,
            active_space_id = dell_space_ids[1],
        },
    }
end

---@return Settings settings the defaults, with the state file of the fake
function fake_worlds.create_default_settings()
    return default_settings.create("/fake/state.json")
end

---@return Timing
function fake_worlds.create_default_timing()
    return fake_worlds.create_default_settings().timing
end

---@param screen_uuid string
---@param screen_frame Rect
---@param space_ids integer[]
---@return ScreenDesktops the desktops of the screen, the first of them in view
function fake_worlds.describe_screen_desktops(screen_uuid, screen_frame, space_ids)
    return {
        screen_uuid = screen_uuid,
        screen_frame = screen_frame,
        space_ids = space_ids,
        active_space_id = space_ids[1],
    }
end

return fake_worlds
