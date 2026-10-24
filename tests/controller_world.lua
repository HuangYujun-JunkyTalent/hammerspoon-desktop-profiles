local fake_hammerspoon = require("tests.fake_hammerspoon")
local fake_worlds = require("tests.fake_worlds")
local profile_controller = require("desktop_manager.macos.profile_controller")
local profile_state = require("desktop_manager.core.profile_state")

---The world of the flow tests of the desktop manager: the fake of Hammerspoon with a running
---controller, and the helpers that read and drive it, which several test files share.
local controller_world = {}

controller_world.BUILTIN_SCREEN = fake_worlds.build_builtin_screen()
controller_world.DELL_SCREEN = fake_worlds.build_dell_screen()
controller_world.SETTLE_SECONDS = 30
controller_world.SEARCH_SHORTCUT = "ctrl+alt+cmd space"
controller_world.MONITOR_CONFIGURATION_KEY = "built-in"
---One second past `periodic_save_seconds` of the default timing, so that the update once a minute
---has run.
controller_world.AFTER_THE_MINUTE_UPDATE_SECONDS = 61

---Saved frames are fractions of the screen rounded to four decimals, so a restored frame is near
---the original frame and not equal to it.
---@param actual Rect
---@param expected Rect
function controller_world.expect_frame_near(actual, expected)
    for _, field in ipairs({ "x", "y", "w", "h" }) do
        if math.abs(actual[field] - expected[field]) > 1 then
            error(
                string.format("expected %s near %g, got %g", field, expected[field], actual[field]),
                2
            )
        end
    end
end

---@param world table
---@param title string
---@return table|nil the window of the fake world with the title
function controller_world.find_window_titled(world, title)
    for _, window in pairs(world.windows) do
        if window.title == title then
            return window
        end
    end
    return nil
end

---@param world table
---@param title string
---@return table the item of the menu bar item with the title
function controller_world.find_menu_item(world, title)
    for _, item in ipairs(world.menu_builder()) do
        if item.title == title then
            return item
        end
    end
    error("the menu has no item " .. title)
end

---@param world table
function controller_world.open_app_pool_window(world)
    controller_world.find_menu_item(world, "Managed applications…").fn()
end

---The busy message is a canvas of a background and one text, one canvas per screen.
---@param world table
---@return string[] shown the texts of the busy messages that showed, in order
---@return integer visible_count the canvases of busy messages that still show
function controller_world.read_busy_messages(world)
    local shown, visible_count = {}, 0
    for _, canvas in ipairs(world.canvases) do
        local elements = canvas.elements
        if #elements == 2 and elements[2].type == "text" then
            table.insert(shown, elements[2].text)
            visible_count = visible_count + (canvas.is_visible and 1 or 0)
        end
    end
    return shown, visible_count
end

---@param controller ProfileController
---@param number integer
---@param window_id integer
---@return WindowRecord|nil the record of the window in the profile for the built-in display alone
function controller_world.find_record(controller, number, window_id)
    local arrangement = profile_state.find_arrangement(
        controller.state,
        number,
        controller_world.MONITOR_CONFIGURATION_KEY
    )
    for _, record in ipairs(arrangement and arrangement.windows or {}) do
        if record.window_id == window_id then
            return record
        end
    end
    return nil
end

---@param controller ProfileController
---@param number integer
---@param window_id integer
---@return string|nil "in sight" or "out of sight" when the profile recorded the window
function controller_world.recorded_sight(controller, number, window_id)
    local record = controller_world.find_record(controller, number, window_id)
    if not record then
        return nil
    end
    return record.is_out_of_sight and "out of sight" or "in sight"
end

---@param setting_changes table|nil settings that replace the defaults, such as concealment_method
---@param saved_state table|nil the state file that the desktop manager finds at its start
---@param seconds_since_macos_start number|nil the time from the start of macOS to the start of the
---desktop manager, an hour when nil
---@param macos_start_time integer|false|nil the start of macOS in seconds since 1970, the same in
---every world when nil, and none that `sysctl` gives when false
---@return table world
---@return ProfileController controller
function controller_world.start_world(
    setting_changes,
    saved_state,
    seconds_since_macos_start,
    macos_start_time
)
    local world = fake_hammerspoon.install({
        seconds_since_macos_start = seconds_since_macos_start,
        macos_start_time = macos_start_time,
        screens = { fake_worlds.build_builtin_screen() },
        displays = { { uuid = "BUILTIN-UUID", space_ids = { 3, 14, 64 }, active_space_id = 3 } },
        applications = {
            {
                bundle_id = "com.apple.Safari",
                name = "Safari",
                is_running = true,
                new_window_title = "Start Page",
            },
            {
                bundle_id = "com.microsoft.Word",
                name = "Microsoft Word",
                is_running = true,
                new_window_title = "Document1",
            },
            {
                bundle_id = "com.apple.Notes",
                name = "Notes",
                is_running = false,
                launch_titles = { "Shopping" },
            },
        },
        windows = {
            {
                id = 41,
                bundle_id = "com.apple.Safari",
                title = "Inbox",
                space_id = 14,
                frame = { x = 0, y = 25, w = 720, h = 875 },
            },
            {
                id = 42,
                bundle_id = "com.microsoft.Word",
                title = "Draft.docx",
                space_id = 3,
                frame = { x = 720, y = 25, w = 720, h = 875 },
            },
        },
    })
    world.saved_json = saved_state
    local settings = fake_worlds.create_default_settings()
    for name, value in pairs(setting_changes or {}) do
        settings[name] = value
    end
    local controller = profile_controller.start(settings)
    return world, controller
end

---A world with the built-in display and a Dell monitor beside it, with a window on the built-in
---display and two windows on the second and third desktops of the monitor.
---@param builtin_space_ids integer[]
---@param dell_space_ids integer[]
---@return table world
---@return ProfileController controller
function controller_world.start_two_screen_world(builtin_space_ids, dell_space_ids)
    local world = fake_hammerspoon.install({
        screens = { controller_world.BUILTIN_SCREEN, controller_world.DELL_SCREEN },
        displays = fake_worlds.build_two_displays(builtin_space_ids, dell_space_ids),
        applications = {
            { bundle_id = "com.apple.Safari", name = "Safari", is_running = true },
            { bundle_id = "com.microsoft.Word", name = "Microsoft Word", is_running = true },
        },
        windows = {
            {
                id = 41,
                bundle_id = "com.apple.Safari",
                title = "Inbox",
                space_id = dell_space_ids[2],
                frame = { x = 1440, y = 25, w = 1280, h = 1390 },
            },
            {
                id = 42,
                bundle_id = "com.microsoft.Word",
                title = "Draft.docx",
                space_id = builtin_space_ids[1],
                frame = { x = 0, y = 25, w = 1440, h = 875 },
            },
            {
                id = 43,
                bundle_id = "com.microsoft.Word",
                title = "Report.docx",
                space_id = dell_space_ids[3],
                frame = { x = 2720, y = 25, w = 1280, h = 1390 },
            },
        },
    })
    local controller = profile_controller.start(fake_worlds.create_default_settings())
    return world, controller
end

---The world of `start_two_screen_world` with Safari in front on the built-in display, and the
---Microsoft Word window "Notes.docx", which Word focused last, on the desktop that the Dell monitor
---shows.
---Each press takes effect after about one second, and the fake models the bounce shortly after.
---@return table world
---@return table notes the window "Notes.docx"
function controller_world.start_bounce_world()
    local world = controller_world.start_two_screen_world({ 3, 14, 64 }, { 7, 8, 9, 10 })
    local news = world.add_window_of("com.apple.Safari", "News", 3)
    local notes = world.add_window_of("com.microsoft.Word", "Notes.docx", 7)
    world.focused_window_id = news.id
    world.applications["com.microsoft.Word"].focused_window_id = notes.id
    world.desktop_press_delay_seconds = 1.01
    world.bounce_delay_seconds = 0.02
    return world, notes
end

---Runs an action and returns the lines that the tools wrote to the console during it.
---@param world table
---@param action fun()
---@return string[]
function controller_world.record_log_lines(world, action)
    local first_index = #world.log_lines + 1
    action()
    return { table.unpack(world.log_lines, first_index) }
end

return controller_world
