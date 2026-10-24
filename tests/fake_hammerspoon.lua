---A fake of the parts of Hammerspoon that the tools call, for tests of the controller flows.
---The fake models screens, desktops, windows and applications.
---It checks the logic of the tools, and says nothing about what macOS 27 really does.
---A minimized window keeps its desktop, as `hs.spaces.windowSpaces` showed on macOS 27.0.1, and an
---unminimize puts the window back on that desktop, as macOS 27.0.1 does.
local fake_hammerspoon = {}

---@class FakeWindowSpec
---@field id integer
---@field bundle_id string
---@field title string
---@field space_id integer
---@field frame Rect
---@field is_standard boolean|nil false for a panel such as the search window of a launcher
---@field is_unseen boolean|nil true for a window on a desktop that the user has not visited since
---Hammerspoon started, which accessibility does not reach until its desktop shows, unless its
---application is hidden
---A test sets `is_ordered_out` on `world.windows[id]` for a window that its application keeps
---after it closed, which shows nowhere: accessibility never reaches it, and the fake of
---`list_server_windows.js` prints it with `is_shown` false.
---A test sets `is_on_every_desktop` on `world.windows[id]` after the install for a window that
---macOS shows on every desktop of its display, which `hs.spaces.windowSpaces` and
---`hs.spaces.windowsForSpace` then list on each of them.
---A test sets `role` on `world.windows[id]` after the install for an element of `allWindows` that
---accessibility gives another role than `AXWindow`, such as `AXSheet`, which `isStandard` and the
---window filter then reject.
---A test sets `is_missed_by_filter` on `world.windows[id]` for a window that the window filter
---leaves out while `allWindows` of its application gives it.

---@class FakeApplicationSpec
---@field bundle_id string
---@field name string
---@field is_running boolean
---@field launch_titles string[]|nil the titles of the windows that a launch opens
---@field new_window_title string|nil the title of the window that the menu item New Window opens
---@field reopen_title string|nil the title of the window that a reopen opens
---A test sets these fields on `world.applications[bundle_id]` after the install:
---`is_dropped_by_filter_while_hidden` makes the window filter leave out the windows of the hidden
---application, and `isStandard` of each of them false, as Hammerspoon does with a window that
---reports another subrole while hidden, such as `AXDialog`.
---`kind` is the value of `kind()`, 1 for an application with a Dock icon by default, and 0 for one
---without.
---`ignores_unhide` makes an unhide leave the application hidden.
---`hidden_read_error` makes `isHidden` raise that error.
---`standard_delay_after_unhide_seconds` is the time after an unhide during which the windows of an
---application with `is_dropped_by_filter_while_hidden` still report another subrole, 0 by default.
---`main_window_id` names the window that `mainWindow` gives, and without it `mainWindow` gives nil.
---`focused_window_id` names the window of the application that had the focus last, which a focus
---of a window of the application sets.
---`focusedWindow` gives that window while its desktop shows, and nil otherwise, as accessibility
---gives AXFocusedWindow only for a window in view.
---Without the field, `focusedWindow` gives the focused window of the world when it belongs to the
---application.
---`activation_delay_seconds` is the time after a focus of a window of the application until the
---window has the focus of the world, which makes the application frontmost, 0 by default.
---`math.huge` keeps the application from becoming frontmost.

---@class FakeDisplaySpec
---@field uuid string
---@field space_ids integer[] the desktops of the display
---@field active_space_id integer a desktop, or a space in full screen
---@field full_screen_space_ids integer[]|nil the spaces of the windows in full screen, which follow
---the desktops in Mission Control unless `all_space_ids` orders them
---@field all_space_ids integer[]|nil the order of the desktops and the spaces in full screen in
---Mission Control, such as a space in full screen between two desktops, and a desktop that it
---leaves out, such as one added later, follows the others

---@class FakeWorldSpec
---@field screens { id: integer, uuid: string, name: string, frame: Rect }[]
---@field displays FakeDisplaySpec[]
---@field applications FakeApplicationSpec[]
---@field windows FakeWindowSpec[]
---@field seconds_since_macos_start number|nil the time from the start of macOS to the start of the
---world on the clock of `hs.timer.absoluteTime()`, an hour by default, so that a world starts long
---after the start of macOS
---@field macos_start_time integer|false|nil the start of macOS in seconds since 1970, which the
---fake gives as `sysctl -n kern.boottime` does, the same in every world by default, so that a
---world started from the state file of another runs under the same start of macOS, and false
---makes `sysctl` give no output

local USER_SPACE_TYPE = 0
local FULL_SCREEN_SPACE_TYPE = 4
local ESCAPE_KEY_CODE = 53
---The key codes of the keys that the lists act on, and the code that the fake gives a typed
---character, which names no key.
local KEY_CODES = {
    escape = ESCAPE_KEY_CODE,
    ["return"] = 36,
    padenter = 76,
    delete = 51,
    tab = 48,
    up = 126,
    down = 125,
    left = 123,
    right = 124,
}
for index, digit in ipairs({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }) do
    KEY_CODES[digit] = ({ 18, 19, 20, 21, 23, 22, 26, 28, 25, 29 })[index]
end
for index, letter in ipairs({ "a", "s", "d", "f", "h", "g", "z", "x", "c", "v" }) do
    KEY_CODES[letter] = index - 1
end
KEY_CODES.space = 49
local CHARACTER_KEY_CODE = 1000
---The output of the fake of `list_server_windows.js`, which the fake of hs.json.decode reads.
local SERVER_WINDOWS_OUTPUT = "server windows"
local OSASCRIPT_PATH = "/usr/bin/osascript"
---The status with which a task that Hammerspoon terminated ends, the number of SIGTERM.
local TERMINATED_STATUS = 15
---The size of the capture of every window in the fake of the helper of the previews.
local CAPTURE_PIXELS = { w = 1200, h = 600 }
local DATA_URL_PREFIX = "data:image/png;base64,"
local NANOSECONDS_PER_SECOND = 1e9
local FIRST_PID = 500
local WINDOW_MANAGER_BUNDLE_ID = "com.apple.WindowManager"

local SYMBOLIC_HOTKEYS_EXPORT = "defaults export com.apple.symbolichotkeys -"
local MACOS_START_TIME_COMMAND = "/usr/sbin/sysctl -n kern.boottime"
local DEFAULT_MACOS_START_TIME = 1729500000

---The world of the last install, where the loggers write, because a module keeps the logger that
---it made under an earlier install.
local current_world = nil

---A test sets these fields of the world after the install:
---`ignores_desktop_presses` makes a press on the thumbnail of a desktop in Mission Control do
---nothing, so that a test can check the failure.
---`ignored_desktop_press_count` is the number of presses on a thumbnail that Mission Control
---ignores before it takes one.
---`desktop_press_delay_seconds` is the time after which a press on a thumbnail takes effect.
---Mission Control keeps showing its groups until then, a further press changes nothing, and a
---toggle of Mission Control drops the press, closes Mission Control and leaves the desktop as it
---was.
---`mission_control_close_delay_seconds` is the time that the groups keep showing after a press has
---made its desktop active.
---`desktop_press_refusals[n]` is the message with which the press number n on a thumbnail fails.
---`makes_thumbnails_stale` makes each press on a thumbnail turn every thumbnail read before it into
---an element that refuses its actions, as an element of accessibility may go stale.
---No measurement on macOS 27.0.1 shows what Mission Control does during its animation, so these
---fields stand for possible behaviours that no measurement has confirmed.
---The fake records each press on a thumbnail in `desktop_presses`, with its desktop, its time and
---the number of reads of the accessibility tree of WindowManager before it, which
---`window_manager_reads` counts.
---`log_lines` holds the lines that the tools write to the loggers of Hammerspoon.
---`focused_display_uuid` names the display of the focus, the first display while it is nil, and
---the focus of a window moves the focus to its display.
---`press_moves_focus`, true by default, makes a press on a thumbnail move the focus to its display,
---which no check on macOS 27.0.1 has confirmed yet.
---`reach_delay_seconds` is the time after which accessibility reaches a window that a press or a
---move by id brought into view, 0 by default.
---`unreachable_window_ids` holds the windows that accessibility does not reach in view either.
---`move_call_seconds` is the time that each call of `hs.spaces.moveWindowToSpace` takes.
---`all_windows_calls` counts the calls of `hs.window.allWindows`, also the call of
---`hs.application.get` that finds no running application and then searches every window, as
---Hammerspoon does, and
---`application_window_reads[bundle_id]` the calls of `allWindows` of each application.
---`hidden_reads[bundle_id]` counts the calls of `isHidden` of each application, and
---`focused_window_reads[bundle_id]` the calls of `focusedWindow` and `mainWindow`.
---`icon_reads[bundle_id]` counts the calls of `hs.image.imageFromAppBundle` for each application.
---`bundle_ids_without_icon` holds the bundle ids for which `hs.image.imageFromAppBundle` gives no
---icon.
---`filter_reads` counts the calls of `getWindows` of the window filter.
---`windows_without_application[window_id]` makes `application` of the window give nil, as
---Hammerspoon may give for a window whose application quits.
---Each canvas counts the calls of its `replaceElements` in `replace_count`.
---The fake of the helper of the previews, `capture_window_previews.js`, gives its first line
---`helper_start_seconds` after its start, 0.15 by default, and each line takes `snapshot_seconds`,
---0.05 by default, which the line also reports as the time of its capture.
---`gives_helper_lines_at_once` makes the helper give all its lines in one chunk after the last
---capture.
---The helper then ends with `helper_exit_code`, 0 by default.
---`helpers` records each helper with its `arguments`, whether it `is_running` and whether it
---`is_terminated`, `snapshot_count` counts the captures, and `rendered_sizes[window_id]` holds the
---size in pixels of the last preview of each window, a capture of 1200 by 600 pixels scaled into
---the box of the helper.
---A missing or minimized window gives no image.
---`last_helper_line_route` sets how the last line of a helper comes: through the streaming
---callback before the exit when it is nil, with the exit as the output of the exit callback under
---`"exit_output"`, or after the exit through the streaming callback with no task under
---`"stream_after_exit"`.
---On macOS 27.0.1, Hammerspoon gave the last line of the helper with the exit in two of three runs,
---and its documentation names the streaming callback after the exit.
---`garbled_window_ids[window_id]` makes the helper give a line for the window that holds no time
---and no image.
---`decode_seconds`, 0 by default, is the time that `hs.image.imageFromURL` takes.
---`is_server_list_above_64_kib` makes the list of the window server too long for a task without a
---streaming callback, which then never ends, as a task of Hammerspoon on macOS 27.0.1 did.
---`on_mission_control_open` is called each time a toggle opens Mission Control.
---`key_wait_seconds`, 0 by default, is how long before its handling each key of `press_key`,
---`type_keys` and `release_modifiers` was made, as `timestamp()` of the event gives it.
---With `key_wait_seconds` nil, each such key carries the timestamp 0, as a key that a program made.
---`move_delay_seconds` is the time after which `hs.spaces.moveWindowToSpace` moves a window, as a
---build with pull request #3889 moves it after the call returns.
---`unmovable_window_ids` holds the windows that `hs.spaces.moveWindowToSpace` leaves where they
---are while it returns true, as Hammerspoon 1.1.1 does on macOS 27.
---`frame_refusing_window_ids` holds the windows whose frame stays when the tool sets one.
---`swallows_timer_errors` makes an error in a timer go into `timer_errors` instead of the test, as
---Hammerspoon logs such an error and goes on.
---`desktop_read_error` makes `hs.spaces.data_managedDisplaySpaces` raise that error.
---`bounce_delay_seconds`, nil by default, models the return to the replaced desktop that the README
---describes under the limits of Hammerspoon and macOS 27.0.1.
---When a press on a thumbnail shows a desktop whose front window belongs to an application that is
---not frontmost, and the focused window of that application lies on the desktop that the press
---replaced, the fake shows the replaced desktop again after `bounce_delay_seconds`.
---The application is then frontmost with that window focused.
---The fake records each bounce in `bounces`, with the desktop shown, the desktop shown again and
---the time.
---`on_window_manager_read` is called at each read of the accessibility tree of WindowManager.
---`execute_calls` counts the calls of `hs.execute` that export the shortcuts of macOS.
---`unwritable_paths[path]` makes `hs.json.write` fail for that path and leave the file as it was.
---@param spec FakeWorldSpec
---@return table world
function fake_hammerspoon.install(spec)
    local world = {
        clock = 0,
        macos_start_offset_seconds = spec.seconds_since_macos_start or 3600,
        macos_start_time = spec.macos_start_time == nil and DEFAULT_MACOS_START_TIME
            or spec.macos_start_time,
        timers = {},
        screens = spec.screens,
        displays = spec.displays,
        applications = {},
        windows = {},
        window_order = {},
        window_operations = {},
        held_modifiers = {},
        key_strokes = {},
        symbolic_hotkeys = {},
        execute_calls = 0,
        tasks = {},
        task_exit_code = 0,
        alerts = {},
        notifications = {},
        hotkeys = {},
        app_hotkeys = {},
        hotkey_by_shortcut = {},
        hotkey_events = {},
        window_moves = {},
        move_delay_seconds = 0.1,
        unmovable_window_ids = {},
        frame_refusing_window_ids = {},
        frames_set_out_of_view = {},
        windows_moved_by_removal = {},
        swallows_timer_errors = false,
        timer_errors = {},
        event_taps = {},
        snapshot_count = 0,
        rendered_sizes = {},
        snapshot_seconds = 0.05,
        helpers = {},
        helper_start_seconds = 0.15,
        gives_helper_lines_at_once = false,
        helper_exit_code = 0,
        last_helper_line_route = nil,
        garbled_window_ids = {},
        decode_seconds = 0,
        is_server_list_above_64_kib = false,
        overlay = nil,
        canvases = {},
        focused_window_id = nil,
        url_handlers = {},
        filter_callbacks = {},
        application_watchers = {},
        screen_watchers = {},
        menu_selections = {},
        saved_json = nil,
        json_files = {},
        unwritable_paths = {},
        windows_without_application = {},
        webview_message_callbacks = {},
        shortcuts_file_path = "/fake/keyboard-shortcuts.json",
        next_window_id = 1000,
        next_space_id = 2000,
        is_mission_control_open = false,
        mission_control_openings = 0,
        mission_control_actions = {},
        ignores_desktop_presses = false,
        ignored_desktop_press_count = 0,
        desktop_press_delay_seconds = 0,
        mission_control_close_delay_seconds = 0,
        desktop_press_refusals = {},
        makes_thumbnails_stale = false,
        desktop_presses = {},
        bounce_delay_seconds = nil,
        bounces = {},
        on_window_manager_read = nil,
        window_manager_reads = 0,
        pending_desktop_press = nil,
        pending_close = nil,
        log_lines = {},
        focused_display_uuid = nil,
        press_moves_focus = true,
        reach_delay_seconds = 0,
        unreachable_window_ids = {},
        move_call_seconds = 0,
        all_windows_calls = 0,
        application_window_reads = {},
        hidden_reads = {},
        focused_window_reads = {},
        icon_reads = {},
        bundle_ids_without_icon = {},
        filter_reads = 0,
        on_mission_control_open = nil,
        key_wait_seconds = 0,
        window_levels = { overlay = 102, screenSaver = 1000 },
    }
    current_world = world

    local function find_screen_at(frame)
        local center_x = frame.x + frame.w / 2
        for _, screen in ipairs(world.screens) do
            if center_x >= screen.frame.x and center_x < screen.frame.x + screen.frame.w then
                return screen
            end
        end
        return world.screens[1]
    end

    local function find_display(uuid)
        for _, display in ipairs(world.displays) do
            if display.uuid == uuid then
                return display
            end
        end
        return nil
    end

    ---@param space_id integer
    ---@return table|nil the display whose desktops or spaces in full screen hold the space
    local function find_display_of_space(space_id)
        for _, display in ipairs(world.displays) do
            for _, candidate in ipairs(display.space_ids) do
                if candidate == space_id then
                    return display
                end
            end
            for _, candidate in ipairs(display.full_screen_space_ids or {}) do
                if candidate == space_id then
                    return display
                end
            end
        end
        return nil
    end

    ---@param display table
    ---@return { space_id: integer, type: integer }[] the desktops and the spaces in full screen of
    ---the display, in the order of Mission Control
    local function list_typed_spaces(display)
        local type_by_space = {}
        for _, space_id in ipairs(display.space_ids) do
            type_by_space[space_id] = USER_SPACE_TYPE
        end
        for _, space_id in ipairs(display.full_screen_space_ids or {}) do
            type_by_space[space_id] = FULL_SCREEN_SPACE_TYPE
        end
        local spaces, is_listed = {}, {}
        local function add(space_id)
            if type_by_space[space_id] and not is_listed[space_id] then
                is_listed[space_id] = true
                table.insert(spaces, { space_id = space_id, type = type_by_space[space_id] })
            end
        end
        for _, space_id in ipairs(display.all_space_ids or {}) do
            add(space_id)
        end
        for _, space_id in ipairs(display.space_ids) do
            add(space_id)
        end
        for _, space_id in ipairs(display.full_screen_space_ids or {}) do
            add(space_id)
        end
        return spaces
    end

    ---@param display table
    ---@return integer[] every space of the display, in the order of Mission Control
    local function list_all_spaces(display)
        local space_ids = {}
        for _, space in ipairs(list_typed_spaces(display)) do
            table.insert(space_ids, space.space_id)
        end
        return space_ids
    end

    local screen_objects = {}
    local screen_object_by_id = {}
    ---Builds the hs.screen objects of the screens of the world again, in the tables that the fake
    ---hands out, after a screen connects or disconnects.
    local function rebuild_screen_objects()
        for index = #screen_objects, 1, -1 do
            screen_objects[index] = nil
        end
        for id in pairs(screen_object_by_id) do
            screen_object_by_id[id] = nil
        end
        for _, screen in ipairs(world.screens) do
            local object = {}
            function object:getUUID()
                return screen.uuid
            end
            function object:name()
                return screen.name
            end
            function object:id()
                return screen.id
            end
            function object:frame()
                local frame = screen.frame
                return { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
            end
            object.fullFrame = object.frame
            table.insert(screen_objects, object)
            screen_object_by_id[screen.id] = object
        end
    end
    rebuild_screen_objects()

    local new_timer
    local mission_control_element
    local schedule_bounce

    ---An accessibility element whose attributes may be functions, read at each call, and whose
    ---actions are functions, which return a message when they refuse.
    ---@param attributes table<string, any>
    ---@param actions table<string, fun(): string|nil>
    ---@return table
    local function accessibility_element(attributes, actions)
        return {
            attributeValue = function(_, name)
                local value = attributes[name]
                if type(value) == "function" then
                    return value()
                end
                return value
            end,
            performAction = function(_, name)
                local action = actions[name]
                if not action then
                    return nil, "the element has no action " .. name
                end
                local refusal = action()
                if refusal then
                    return nil, refusal
                end
                return true
            end,
        }
    end

    ---Lets accessibility reach a window that Hammerspoon had not seen, once a press or a move by id
    ---brought it into view, after `reach_delay_seconds`, and never for `unreachable_window_ids`.
    ---@param window table
    local function reveal(window)
        if not window.is_unseen or world.unreachable_window_ids[window.id] then
            return
        end
        if world.reach_delay_seconds > 0 then
            new_timer(world.reach_delay_seconds, function()
                window.is_unseen = false
            end, false)
            return
        end
        window.is_unseen = false
    end

    local window_manager_application = {}
    function window_manager_application:bundleID()
        return WINDOW_MANAGER_BUNDLE_ID
    end

    ---@param space_id integer
    ---@return table|nil the window at the front of the desktop, the first of `window_order` on it
    ---that shows
    local function find_front_window(space_id)
        for _, window_id in ipairs(world.window_order) do
            local window = world.windows[window_id]
            if
                window.space_id == space_id
                and not window.is_minimized
                and not world.applications[window.bundle_id].is_hidden
            then
                return window
            end
        end
        return nil
    end

    ---Shows the replaced desktop again after `bounce_delay_seconds`, when the application of the
    ---front window of the shown desktop is not frontmost and its focused window lies on the
    ---replaced desktop.
    ---@param display table a display of the world
    ---@param replaced_space_id integer
    ---@param space_id integer the desktop that the press showed
    schedule_bounce = function(display, replaced_space_id, space_id)
        local front = world.bounce_delay_seconds and find_front_window(space_id)
        if not front then
            return
        end
        local focused = world.focused_window_id and world.windows[world.focused_window_id]
        if focused and focused.bundle_id == front.bundle_id then
            return
        end
        local returning_id = world.applications[front.bundle_id].focused_window_id
        local returning = returning_id and world.windows[returning_id]
        if not returning or returning.space_id ~= replaced_space_id then
            return
        end
        new_timer(world.bounce_delay_seconds, function()
            display.active_space_id = replaced_space_id
            world.focused_window_id = returning.id
            world.focused_display_uuid = display.uuid
            table.insert(world.bounces, {
                shown_space_id = space_id,
                shown_again_space_id = replaced_space_id,
                at = world.clock,
            })
        end, false)
    end

    ---@param display table a display of the world
    ---@param space_id integer
    ---@return table the thumbnail of a desktop in the list of Mission Control: a press shows the
    ---desktop and closes Mission Control, and macOS removes no desktop that shows
    local function desktop_thumbnail(display, space_id)
        local function show_desktop()
            local replaced_space_id = display.active_space_id
            display.active_space_id = space_id
            schedule_bounce(display, replaced_space_id, space_id)
            for _, window in pairs(world.windows) do
                if window.space_id == space_id then
                    reveal(window)
                end
            end
            if world.mission_control_close_delay_seconds > 0 then
                local pending_close = {}
                world.pending_close = pending_close
                new_timer(world.mission_control_close_delay_seconds, function()
                    if world.pending_close == pending_close then
                        world.pending_close = nil
                        world.is_mission_control_open = false
                    end
                end, false)
            else
                world.is_mission_control_open = false
            end
            if world.press_moves_focus then
                world.focused_display_uuid = display.uuid
            end
            table.insert(world.mission_control_actions, "show " .. space_id)
        end
        local presses_at_read = #world.desktop_presses
        return accessibility_element({ AXIdentifier = "mc.space" }, {
            AXPress = function()
                if world.makes_thumbnails_stale and presses_at_read < #world.desktop_presses then
                    return "the element is stale"
                end
                table.insert(world.desktop_presses, {
                    space_id = space_id,
                    at = world.clock,
                    window_manager_reads = world.window_manager_reads,
                })
                local refusal = world.desktop_press_refusals[#world.desktop_presses]
                if refusal then
                    return refusal
                end
                if world.ignores_desktop_presses or world.pending_desktop_press then
                    return nil
                end
                if world.ignored_desktop_press_count > 0 then
                    world.ignored_desktop_press_count = world.ignored_desktop_press_count - 1
                    return nil
                end
                if world.desktop_press_delay_seconds > 0 then
                    local pending_press = {}
                    world.pending_desktop_press = pending_press
                    new_timer(world.desktop_press_delay_seconds, function()
                        if world.pending_desktop_press == pending_press then
                            world.pending_desktop_press = nil
                            show_desktop()
                        end
                    end, false)
                    return nil
                end
                show_desktop()
                return nil
            end,
            AXRemoveDesktop = function()
                if display.active_space_id == space_id then
                    return "the desktop shows"
                end
                for index = #display.space_ids, 1, -1 do
                    if display.space_ids[index] == space_id then
                        table.remove(display.space_ids, index)
                    end
                end
                for _, window_id in ipairs(world.window_order) do
                    local window = world.windows[window_id]
                    if window.space_id == space_id then
                        window.space_id = display.space_ids[1]
                        local is_hidden = world.applications[window.bundle_id].is_hidden
                        if not window.is_minimized and not is_hidden then
                            table.insert(world.windows_moved_by_removal, window_id)
                        end
                    end
                end
                table.insert(world.mission_control_actions, "remove " .. space_id)
                return nil
            end,
        })
    end

    ---The tree of Mission Control under the process WindowManager, as macOS 27 keeps it: a group
    ---per display, with the button that adds a desktop and the list of the desktops.
    ---@return table
    mission_control_element = function()
        local groups = {}
        for _, screen in ipairs(world.screens) do
            local display = find_display(screen.uuid)
            local add_button = accessibility_element({ AXIdentifier = "mc.spaces.add" }, {
                AXPress = function()
                    local space_id = world.next_space_id
                    world.next_space_id = space_id + 1
                    table.insert(display.space_ids, space_id)
                    table.insert(world.mission_control_actions, "add " .. space_id)
                    return nil
                end,
            })
            local spaces_list = accessibility_element({
                AXIdentifier = "mc.spaces.list",
                AXChildren = function()
                    local thumbnails = {}
                    for _, space_id in ipairs(list_all_spaces(display)) do
                        table.insert(thumbnails, desktop_thumbnail(display, space_id))
                    end
                    return thumbnails
                end,
            }, {})
            table.insert(
                groups,
                accessibility_element({
                    AXIdentifier = "mc.display",
                    AXDisplayID = screen.id,
                    AXChildren = { add_button, spaces_list },
                }, {})
            )
        end
        return accessibility_element({ AXChildren = groups }, {})
    end

    ---Whether the windows of the application report another subrole than a standard window: while
    ---it is hidden, and for `standard_delay_after_unhide_seconds` after its unhide.
    ---@param application table an application of the fake world
    ---@return boolean
    local function reports_other_subrole(application)
        return application.is_dropped_by_filter_while_hidden == true
            and (application.is_hidden or world.clock < (application.standard_again_at or 0))
    end

    local application_objects = {}
    local function application_object(bundle_id)
        if application_objects[bundle_id] then
            return application_objects[bundle_id]
        end
        local application = world.applications[bundle_id]
        local object = {}
        function object:bundleID()
            return bundle_id
        end
        function object:name()
            return application.name
        end
        function object:pid()
            return application.pid
        end
        function object:kind()
            return application.kind or 1
        end
        function object:isHidden()
            world.hidden_reads[bundle_id] = (world.hidden_reads[bundle_id] or 0) + 1
            if application.hidden_read_error then
                error(application.hidden_read_error)
            end
            return application.is_hidden
        end
        function object:hide()
            local was_hidden = application.is_hidden
            application.is_hidden = true
            if not was_hidden then
                for _, watcher in ipairs(world.application_watchers) do
                    watcher(application.name, hs.application.watcher.hidden, object)
                end
            end
            return true
        end
        function object:unhide()
            if application.ignores_unhide then
                return false
            end
            local was_hidden = application.is_hidden
            application.is_hidden = false
            if was_hidden then
                application.standard_again_at = world.clock
                    + (application.standard_delay_after_unhide_seconds or 0)
                for _, watcher in ipairs(world.application_watchers) do
                    watcher(application.name, hs.application.watcher.unhidden, object)
                end
            end
            return true
        end
        function object:selectMenuItem(item)
            local title = application.new_window_title
            if item ~= "New Window" or not title then
                return nil
            end
            table.insert(world.menu_selections, bundle_id .. " " .. item)
            new_timer(0.2, function()
                world.create_window(bundle_id, title)
            end, false)
            return true
        end
        ---Whether accessibility reaches the window: a window in view once its desktop has shown,
        ---and while the application is hidden also a window on a desktop that has not shown,
        ---as the README of the repository says.
        ---@param window table a window of the fake world
        ---@return boolean
        local function is_reached(window)
            if window.is_ordered_out or world.unreachable_window_ids[window.id] then
                return false
            end
            return not window.is_unseen or application.is_hidden == true
        end
        local function count_focused_window_read()
            world.focused_window_reads[bundle_id] = (world.focused_window_reads[bundle_id] or 0) + 1
        end
        function object:focusedWindow()
            count_focused_window_read()
            local window_id = application.focused_window_id
            local world_focused = world.focused_window_id and world.windows[world.focused_window_id]
            if not window_id and world_focused and world_focused.bundle_id == bundle_id then
                window_id = world_focused.id
            end
            local window = window_id and world.windows[window_id]
            if not window or not is_reached(window) or window.is_minimized then
                return nil
            end
            local display = find_display_of_space(window.space_id)
            if not display or display.active_space_id ~= window.space_id then
                return nil
            end
            return window.object
        end
        function object:mainWindow()
            count_focused_window_read()
            local window = world.windows[application.main_window_id]
            if not window or not is_reached(window) then
                return nil
            end
            return window.object
        end
        function object:allWindows()
            world.application_window_reads[bundle_id] = (
                world.application_window_reads[bundle_id] or 0
            ) + 1
            local windows = {}
            for _, window_id in ipairs(world.window_order) do
                local window = world.windows[window_id]
                if window.bundle_id == bundle_id and is_reached(window) then
                    table.insert(windows, window.object)
                end
            end
            return windows
        end
        application_objects[bundle_id] = object
        return object
    end

    local function active_space_at(frame)
        local display = find_display(find_screen_at(frame).uuid)
        return display and display.active_space_id
    end

    local function emit_filter_event(event, window)
        local callback = world.filter_callbacks[event]
        if callback then
            callback(window.object, world.applications[window.bundle_id].name, event)
        end
    end

    ---@param operation string
    ---@param window table
    local function record_operation(operation, window)
        table.insert(world.window_operations, string.format("%s %d", operation, window.id))
    end

    local function add_window(window_spec)
        local window = {
            id = window_spec.id,
            bundle_id = window_spec.bundle_id,
            title = window_spec.title,
            space_id = window_spec.space_id,
            frame = window_spec.frame,
            is_minimized = false,
            is_standard = window_spec.is_standard,
            is_unseen = window_spec.is_unseen,
        }
        local object = {}
        function object:id()
            return window.id
        end
        function object:focus()
            local application = world.applications[window.bundle_id]
            application.focused_window_id = window.id
            local function take_focus()
                world.focused_window_id = window.id
                local display = find_display_of_space(window.space_id)
                world.focused_display_uuid = display and display.uuid or world.focused_display_uuid
            end
            local delay_seconds = application.activation_delay_seconds or 0
            if delay_seconds > 0 then
                new_timer(delay_seconds, take_focus, false)
            else
                take_focus()
            end
            table.insert(world.window_operations, "focus " .. window.id)
            return object
        end
        function object:isStandard()
            local application = world.applications[window.bundle_id]
            return window.is_standard ~= false
                and object:role() == "AXWindow"
                and not reports_other_subrole(application)
        end
        function object:role()
            return window.role or "AXWindow"
        end
        function object:title()
            return window.title
        end
        function object:application()
            if world.windows_without_application[window.id] then
                return nil
            end
            return application_object(window.bundle_id)
        end
        function object:isMinimized()
            return window.is_minimized
        end
        function object:minimize()
            record_operation("minimize", window)
            window.is_minimized = true
            emit_filter_event("windowMinimized", window)
            return object
        end
        function object:unminimize()
            record_operation("unminimize", window)
            window.is_minimized = false
            emit_filter_event("windowUnminimized", window)
            return object
        end
        function object:frame()
            local frame = window.frame
            return { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
        end
        function object:screen()
            return screen_object_by_id[find_screen_at(window.frame).id]
        end
        function object:setFrame(rect)
            record_operation("setFrame", window)
            local display = find_display_of_space(window.space_id)
            if not display or display.active_space_id ~= window.space_id then
                table.insert(world.frames_set_out_of_view, window.id)
            end
            if world.frame_refusing_window_ids[window.id] then
                return object
            end
            local old_screen, new_screen = find_screen_at(window.frame), find_screen_at(rect)
            window.frame = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
            if old_screen ~= new_screen then
                window.space_id = active_space_at(window.frame)
            end
            return object
        end
        window.object = object
        world.windows[window.id] = window
        table.insert(world.window_order, window.id)
        return window
    end

    for index, application in ipairs(spec.applications) do
        world.applications[application.bundle_id] = {
            name = application.name,
            pid = FIRST_PID + index,
            is_running = application.is_running,
            is_hidden = false,
            launch_titles = application.launch_titles or {},
            new_window_title = application.new_window_title,
            reopen_title = application.reopen_title,
        }
    end
    for _, window_spec in ipairs(spec.windows) do
        add_window(window_spec)
    end

    ---Minimizes a window as a click on its yellow button does.
    ---@param window_id integer
    function world.minimize_window(window_id)
        world.windows[window_id].object:minimize()
    end

    ---Unminimizes a window as a click on it in the Dock does.
    ---@param window_id integer
    function world.unminimize_window(window_id)
        world.windows[window_id].object:unminimize()
    end

    ---Adds a window on a desktop that the user has not visited since Hammerspoon started, which
    ---accessibility reaches once its desktop shows.
    ---@param bundle_id string
    ---@param title string
    ---@param space_id integer
    ---@return table window
    function world.create_unseen_window(bundle_id, title, space_id)
        world.next_window_id = world.next_window_id + 1
        world.applications[bundle_id].is_running = true
        local screen = world.screens[1]
        return add_window({
            id = world.next_window_id,
            bundle_id = bundle_id,
            title = title,
            space_id = space_id,
            frame = { x = screen.frame.x, y = screen.frame.y, w = 600, h = 400 },
            is_unseen = true,
        })
    end

    ---Adds a window that Hammerspoon has seen on any desktop, such as a window of an application
    ---that the desktop manager leaves to macOS, at the top left corner of the screen of the
    ---desktop.
    ---@param bundle_id string
    ---@param title string
    ---@param space_id integer
    ---@return table window
    function world.add_window_of(bundle_id, title, space_id)
        world.next_window_id = world.next_window_id + 1
        world.applications[bundle_id].is_running = true
        local display = find_display_of_space(space_id)
        local screen = world.screens[1]
        for _, candidate in ipairs(world.screens) do
            if display and candidate.uuid == display.uuid then
                screen = candidate
            end
        end
        return add_window({
            id = world.next_window_id,
            bundle_id = bundle_id,
            title = title,
            space_id = space_id,
            frame = { x = screen.frame.x, y = screen.frame.y, w = 600, h = 400 },
        })
    end

    ---@param bundle_id string
    ---@param title string
    ---@return table window
    function world.create_window(bundle_id, title)
        world.next_window_id = world.next_window_id + 1
        local application = world.applications[bundle_id]
        application.is_running = true
        local display = world.displays[1]
        local screen = world.screens[1]
        local window = add_window({
            id = world.next_window_id,
            bundle_id = bundle_id,
            title = title,
            space_id = display.active_space_id,
            frame = { x = screen.frame.x, y = screen.frame.y, w = 600, h = 400 },
        })
        if application.is_hidden then
            application_object(bundle_id):unhide()
        end
        emit_filter_event("windowCreated", window)
        return window
    end

    ---@param event table the fake hs.eventtap.event
    local function send_to_event_taps(event)
        for _, tap in ipairs(world.event_taps) do
            if tap.is_running then
                tap.callback(event)
            end
        end
    end

    ---@return number the time of a key made `key_wait_seconds` ago, in nanoseconds, on the clock of
    ---`hs.timer.absoluteTime()`, or 0 for a key that a program made
    local function read_key_timestamp()
        if world.key_wait_seconds == nil then
            return 0
        end
        return (world.macos_start_offset_seconds + world.clock - world.key_wait_seconds)
            * NANOSECONDS_PER_SECOND
    end

    ---Releases every modifier key, as the user lifts the fingers.
    function world.release_modifiers()
        world.held_modifiers = {}
        send_to_event_taps({
            getType = function()
                return 12
            end,
            getFlags = function()
                return {}
            end,
            timestamp = read_key_timestamp,
        })
    end

    ---Presses a key that hs.keycodes.map names, such as "tab", with the modifiers held.
    ---@param name string
    ---@param flags table<string, boolean>|nil
    function world.press_key(name, flags)
        send_to_event_taps({
            getType = function()
                return 10
            end,
            getKeyCode = function()
                return KEY_CODES[name]
            end,
            getFlags = function()
                return flags or {}
            end,
            getCharacters = function()
                return ""
            end,
            timestamp = read_key_timestamp,
        })
    end

    function world.press_escape()
        world.press_key("escape")
    end

    ---Types the characters one key at a time, without modifiers.
    ---@param text string
    function world.type_keys(text)
        for character in text:gmatch(utf8.charpattern) do
            send_to_event_taps({
                getType = function()
                    return 10
                end,
                getKeyCode = function()
                    return CHARACTER_KEY_CODE
                end,
                getFlags = function()
                    return {}
                end,
                getCharacters = function()
                    return character
                end,
                timestamp = read_key_timestamp,
            })
        end
    end

    ---The texts of the list on the screen, with the selected line marked by ">".
    ---@return string[]|nil
    function world.read_overlay()
        if not world.overlay or not world.overlay.is_visible then
            return nil
        end
        local texts, is_next_selected = {}, false
        for _, element in ipairs(world.overlay.elements) do
            if element.type == "rectangle" and element.id == "selection" then
                is_next_selected = true
            elseif element.type == "text" then
                table.insert(texts, (is_next_selected and ">" or " ") .. element.text)
                is_next_selected = false
            end
        end
        return texts
    end

    ---The parts of the panel of the search on the screen: the two texts of the search line, the
    ---note without windows, and each preview and each application as its mark and its texts.
    ---The mark is the id of the rectangle behind the item, such as "selection", "hovered" or
    ---"match-strong", or "faded" for an item with a faded text, or "plain".
    ---@return table|nil
    function world.read_search_panel()
        if not world.overlay or not world.overlay.is_visible then
            return nil
        end
        local panel = { line = {}, windows = {}, applications = {}, note = nil }
        local texts, mark, is_faded = {}, nil, false
        for _, element in ipairs(world.overlay.elements) do
            if element.type == "rectangle" and element.trackMouseByBounds then
                local kind = element.id:match("^(%a+):")
                local item = (mark or (is_faded and "faded") or "plain")
                    .. " "
                    .. table.concat(texts, " | ")
                table.insert(kind == "window" and panel.windows or panel.applications, item)
                texts, mark, is_faded = {}, nil, false
            elseif
                element.type == "rectangle"
                and element.frame
                and element.id ~= "search-field"
            then
                mark = element.id
            elseif element.type == "text" and #panel.line < 2 then
                table.insert(panel.line, element.text)
            elseif element.type == "text" and element.id == "no-window-note" then
                panel.note = element.text
            elseif element.type == "text" then
                table.insert(texts, element.text)
                is_faded = is_faded or element.id == "faded"
            end
        end
        return panel
    end

    ---@param id string
    ---@param attribute string
    ---@return table the element of the panel on the screen with the id, which tracks the mouse
    local function find_tracking_element(id, attribute)
        for _, element in ipairs(world.overlay.elements) do
            if element.id == id then
                if not element[attribute] or not element.trackMouseByBounds then
                    error(
                        string.format(
                            "the element %s lacks %s or tracking by bounds",
                            id,
                            attribute
                        )
                    )
                end
                return element
            end
        end
        error("the panel on the screen has no element " .. id)
    end

    ---Moves the mouse onto the element with the id, as the user does, which leaves the element
    ---under the mouse before.
    ---@param id string
    function world.move_mouse_to(id)
        find_tracking_element(id, "trackMouseEnterExit")
        local canvas = world.overlay
        if world.mouse_element_id and world.mouse_element_id ~= id then
            canvas.mouse_callback(canvas, "mouseExit", world.mouse_element_id, 0, 0)
        end
        world.mouse_element_id = id
        canvas.mouse_callback(canvas, "mouseEnter", id, 0, 0)
    end

    ---Clicks the element with the id, after moving the mouse onto it.
    ---@param id string
    function world.click(id)
        world.move_mouse_to(id)
        find_tracking_element(id, "trackMouseUp")
        world.overlay.mouse_callback(world.overlay, "mouseUp", id, 0, 0)
    end

    function world.move_mouse_out_of_panel()
        local canvas = world.overlay
        if not (canvas.canvas_mouse_events and canvas.canvas_mouse_events.enter_exit) then
            error("the panel on the screen reports no exit of the mouse")
        end
        if world.mouse_element_id then
            canvas.mouse_callback(canvas, "mouseExit", world.mouse_element_id, 0, 0)
            world.mouse_element_id = nil
        end
        canvas.mouse_callback(canvas, "mouseExit", "_canvas_", 0, 0)
    end

    ---@return string[]|nil the sources of the images of the list on the screen, in order
    function world.read_overlay_images()
        if not world.overlay or not world.overlay.is_visible then
            return nil
        end
        local sources = {}
        for _, element in ipairs(world.overlay.elements) do
            if element.type == "image" then
                table.insert(sources, element.image.source)
            end
        end
        return sources
    end

    ---Closes a window, as a click on its red button does.
    ---@param window_id integer
    function world.close_window(window_id)
        local window = world.windows[window_id]
        world.windows[window_id] = nil
        for index, listed_id in ipairs(world.window_order) do
            if listed_id == window_id then
                table.remove(world.window_order, index)
            end
        end
        emit_filter_event("windowDestroyed", window)
    end

    ---Unhides an application as a click on its icon in the Dock does.
    ---@param bundle_id string
    function world.unhide_application(bundle_id)
        application_object(bundle_id):unhide()
    end

    ---Hides an application as Command-H does.
    ---@param bundle_id string
    function world.hide_application(bundle_id)
        application_object(bundle_id):hide()
    end

    ---Quits an application and reports the quit to the application watchers, and leaves its
    ---windows to the test.
    ---@param bundle_id string
    function world.terminate_application(bundle_id)
        world.applications[bundle_id].is_running = false
        for _, watcher in ipairs(world.application_watchers) do
            watcher(
                world.applications[bundle_id].name,
                hs.application.watcher.terminated,
                application_object(bundle_id)
            )
        end
    end

    ---Reports a quit to the application watchers with the application that the event gives, which
    ---may be nil or an application without a bundle id and a name.
    ---@param application table|nil
    function world.report_quit_of(application)
        for _, watcher in ipairs(world.application_watchers) do
            watcher(nil, hs.application.watcher.terminated, application)
        end
    end

    new_timer = function(seconds, callback, is_repeating)
        local timer = { due = world.clock + seconds, interval = seconds, callback = callback }
        timer.is_repeating = is_repeating
        timer.is_running = true
        function timer:stop()
            timer.is_running = false
            return timer
        end
        table.insert(world.timers, timer)
        return timer
    end

    ---Sends a message of the page of a webview, as the script of the page posts one to its handler.
    ---@param handler_name string the name of the message handler of the page, such as "appPool"
    ---@param body table
    function world.post_to_webview(handler_name, body)
        local callback = world.webview_message_callbacks[handler_name]
        if not callback then
            error("no page of a webview has the message handler " .. handler_name)
        end
        callback({ name = handler_name, body = body })
    end

    ---Disconnects a screen as macOS 27 does while displays have separate Spaces: the first desktop
    ---of the screen goes away and its windows go to the first desktop of the first other screen,
    ---and the other desktops of the screen move to the end of that screen with their windows.
    ---@param uuid string
    function world.disconnect_screen(uuid)
        local display = find_display(uuid)
        local remaining = nil
        for _, candidate in ipairs(world.displays) do
            if candidate ~= display and remaining == nil then
                remaining = candidate
            end
        end
        local remaining_screen = nil
        for _, screen in ipairs(world.screens) do
            if screen.uuid == remaining.uuid then
                remaining_screen = screen
            end
        end
        for position, space_id in ipairs(display.space_ids) do
            if position > 1 then
                table.insert(remaining.space_ids, space_id)
            end
            for _, window in pairs(world.windows) do
                if window.space_id == space_id then
                    window.space_id = position == 1 and remaining.space_ids[1] or space_id
                    local frame = remaining_screen.frame
                    window.frame = {
                        x = frame.x,
                        y = frame.y,
                        w = math.min(window.frame.w, frame.w),
                        h = math.min(window.frame.h, frame.h),
                    }
                end
            end
        end
        for index = #world.displays, 1, -1 do
            if world.displays[index] == display then
                table.remove(world.displays, index)
            end
        end
        for index = #world.screens, 1, -1 do
            if world.screens[index].uuid == uuid then
                table.remove(world.screens, index)
            end
        end
        rebuild_screen_objects()
    end

    ---Connects a screen with the desktops that macOS gives it, the first of them in view.
    ---@param screen { id: integer, uuid: string, name: string, frame: Rect }
    ---@param space_ids integer[]
    function world.connect_screen(screen, space_ids)
        table.insert(world.screens, screen)
        table.insert(
            world.displays,
            { uuid = screen.uuid, space_ids = space_ids, active_space_id = space_ids[1] }
        )
        rebuild_screen_objects()
    end

    ---Calls the callback after the seconds, as a change that macOS makes on its own.
    ---@param seconds number
    ---@param callback fun()
    function world.schedule(seconds, callback)
        new_timer(seconds, callback, false)
    end

    ---Runs the timers that fall due within the seconds, in the order of their due times.
    ---A callback may move the clock on, such as a decode of a preview, and a timer whose due time
    ---the clock has passed then runs at the time of the clock, so the clock never moves back.
    ---@param seconds number
    function world.advance(seconds)
        local target = world.clock + seconds
        while true do
            local next_timer = nil
            for _, timer in ipairs(world.timers) do
                if
                    timer.is_running
                    and timer.due <= target
                    and (not next_timer or timer.due < next_timer.due)
                then
                    next_timer = timer
                end
            end
            if not next_timer then
                break
            end
            world.clock = math.max(world.clock, next_timer.due)
            if next_timer.is_repeating then
                next_timer.due = world.clock + math.max(next_timer.interval, 0.001)
            else
                next_timer.is_running = false
            end
            if world.swallows_timer_errors then
                local is_successful, message = pcall(next_timer.callback)
                if not is_successful then
                    table.insert(world.timer_errors, tostring(message))
                end
            else
                next_timer.callback()
            end
        end
        world.clock = math.max(world.clock, target)
    end

    local function managed_displays()
        if world.desktop_read_error then
            error(world.desktop_read_error)
        end
        local displays = {}
        for _, display in ipairs(world.displays) do
            local spaces = {}
            for _, space in ipairs(list_typed_spaces(display)) do
                table.insert(spaces, { ManagedSpaceID = space.space_id, type = space.type })
            end
            table.insert(displays, {
                ["Display Identifier"] = display.uuid,
                ["Current Space"] = { ManagedSpaceID = display.active_space_id },
                Spaces = spaces,
            })
        end
        return displays
    end

    local function watcher_factory()
        return {
            new = function()
                return {
                    start = function(self)
                        return self
                    end,
                }
            end,
        }
    end

    local application_watcher = {
        hidden = "hidden",
        unhidden = "unhidden",
        terminated = "terminated",
        new = function(callback)
            table.insert(world.application_watchers, callback)
            return {
                start = function(self)
                    return self
                end,
            }
        end,
    }

    local function list_window_objects()
        world.all_windows_calls = world.all_windows_calls + 1
        local windows = {}
        for _, window_id in ipairs(world.window_order) do
            local window = world.windows[window_id]
            if not window.is_unseen and not window.is_ordered_out then
                table.insert(windows, window.object)
            end
        end
        return windows
    end

    local filter_object = {}
    function filter_object:setDefaultFilter()
        return filter_object
    end
    function filter_object:getWindows()
        world.filter_reads = world.filter_reads + 1
        local windows = {}
        for _, window_id in ipairs(world.window_order) do
            local window = world.windows[window_id]
            local application = world.applications[window.bundle_id]
            if
                not window.is_unseen
                and not window.is_ordered_out
                and not window.is_missed_by_filter
                and (window.role or "AXWindow") == "AXWindow"
                and not reports_other_subrole(application)
            then
                table.insert(windows, window.object)
            end
        end
        return windows
    end
    function filter_object:subscribe(callbacks)
        for event, callback in pairs(callbacks) do
            world.filter_callbacks[event] = callback
        end
        return filter_object
    end

    ---@param window_id integer
    ---@param box table the w and h in pixels of the box of the helper
    ---@return string the line of the helper for the window, with its end
    local function capture_window(window_id, box)
        world.snapshot_count = world.snapshot_count + 1
        if world.garbled_window_ids[window_id] then
            return string.format("%d garbled\n", window_id)
        end
        local window = world.windows[window_id]
        if not window or window.is_minimized then
            return string.format("%d %.3f none\n", window_id, world.snapshot_seconds)
        end
        local scale = math.min(box.w / CAPTURE_PIXELS.w, box.h / CAPTURE_PIXELS.h)
        world.rendered_sizes[window_id] = {
            w = math.max(1, math.floor(CAPTURE_PIXELS.w * scale + 0.5)),
            h = math.max(1, math.floor(CAPTURE_PIXELS.h * scale + 0.5)),
        }
        return string.format(
            "%d %.3f %s%d\n",
            window_id,
            world.snapshot_seconds,
            DATA_URL_PREFIX,
            window_id
        )
    end

    ---Runs the fake of `capture_window_previews.js` for the task, which takes the arguments
    ---`-l JavaScript <script> <box width> <box height> <window id> ...`.
    ---@param task table
    ---@param on_exit fun(exit_code: integer, output: string, error_output: string)
    ---@param on_output fun(task: table|nil, output: string, error_output: string)
    ---@param arguments string[]
    local function start_fake_helper(task, on_exit, on_output, arguments)
        local box = { w = tonumber(arguments[4]), h = tonumber(arguments[5]) }
        local window_ids = {}
        for index = 6, #arguments do
            table.insert(window_ids, math.tointeger(tonumber(arguments[index])))
        end
        local helper = { arguments = arguments, is_running = true, is_terminated = false }
        table.insert(world.helpers, helper)
        local timers = {}
        local function after(seconds, callback)
            table.insert(timers, new_timer(seconds, callback, false))
        end
        function task:isRunning()
            return helper.is_running
        end
        function task:terminate()
            if helper.is_running then
                helper.is_running = false
                helper.is_terminated = true
                for _, timer in ipairs(timers) do
                    timer:stop()
                end
                new_timer(0, function()
                    on_exit(TERMINATED_STATUS, "", "")
                end, false)
            end
            return task
        end
        local last_line_seconds = world.helper_start_seconds + #window_ids * world.snapshot_seconds
        local route = world.last_helper_line_route
        if world.gives_helper_lines_at_once then
            after(last_line_seconds, function()
                local lines = {}
                for _, window_id in ipairs(window_ids) do
                    table.insert(lines, capture_window(window_id, box))
                end
                on_output(task, table.concat(lines), "")
            end)
        else
            for position, window_id in ipairs(window_ids) do
                if position < #window_ids or route == nil then
                    after(world.helper_start_seconds + position * world.snapshot_seconds, function()
                        on_output(task, capture_window(window_id, box), "")
                    end)
                end
            end
        end
        after(last_line_seconds, function()
            helper.is_running = false
            local is_last_line_left = route ~= nil and not world.gives_helper_lines_at_once
            local last_line = is_last_line_left and capture_window(window_ids[#window_ids], box)
            on_exit(world.helper_exit_code, route == "exit_output" and last_line or "", "")
            if route == "stream_after_exit" and last_line then
                on_output(nil, last_line, "")
            end
        end)
        return task
    end

    _G.hs = {
        configdir = "/fake/.hammerspoon",
        processInfo = { version = "8cde946" },
        accessibilityState = function()
            return true
        end,
        focus = function() end,
        inspect = function()
            return "<inspected>"
        end,
        timer = {
            secondsSinceEpoch = function()
                return world.clock
            end,
            absoluteTime = function()
                return (world.macos_start_offset_seconds + world.clock) * NANOSECONDS_PER_SECOND
            end,
            doAfter = function(seconds, callback)
                return new_timer(seconds, callback, false)
            end,
            doEvery = function(seconds, callback)
                return new_timer(seconds, callback, true)
            end,
        },
        screen = {
            allScreens = function()
                return screen_objects
            end,
            primaryScreen = function()
                return screen_objects[1]
            end,
            mainScreen = function()
                return screen_objects[1]
            end,
            watcher = {
                new = function(callback)
                    table.insert(world.screen_watchers, callback)
                    return {
                        start = function(self)
                            return self
                        end,
                    }
                end,
            },
        },
        spaces = {
            data_managedDisplaySpaces = managed_displays,
            focusedSpace = function()
                local display = world.focused_display_uuid
                    and find_display(world.focused_display_uuid)
                return (display or world.displays[1]).active_space_id
            end,
            windowSpaces = function(window_id)
                local window = world.windows[window_id]
                if not window then
                    return {}
                end
                local display = window.is_on_every_desktop
                    and find_display_of_space(window.space_id)
                if display then
                    return { table.unpack(display.space_ids) }
                end
                return { window.space_id }
            end,
            ---Moves the window after `move_delay_seconds`, and a window that arrives on the desktop
            ---in view becomes one that Hammerspoon has seen.
            ---A desktop of another display raises an error, because the tool moves a window to
            ---another screen by its frame alone.
            moveWindowToSpace = function(window_id, space_id)
                table.insert(world.window_moves, string.format("%d to %d", window_id, space_id))
                local window = world.windows[window_id]
                if not window then
                    return true
                end
                local display = find_display_of_space(space_id)
                if not display or display ~= find_display_of_space(window.space_id) then
                    error(string.format("desktop %d is on another display", space_id))
                end
                world.clock = world.clock + world.move_call_seconds
                if world.unmovable_window_ids[window_id] then
                    return true
                end
                new_timer(world.move_delay_seconds, function()
                    window.space_id = space_id
                    if display.active_space_id == space_id then
                        reveal(window)
                    end
                end, false)
                return true
            end,
            windowsForSpace = function(space_id)
                local window_ids = {}
                for _, window_id in ipairs(world.window_order) do
                    local window = world.windows[window_id]
                    local is_on_space = window.space_id == space_id
                        or window.is_on_every_desktop
                            and find_display_of_space(window.space_id) == find_display_of_space(
                                space_id
                            )
                    if is_on_space and not window.is_minimized then
                        table.insert(window_ids, window_id)
                    end
                end
                return window_ids
            end,
            toggleMissionControl = function()
                world.pending_close = nil
                if world.pending_desktop_press then
                    world.pending_desktop_press = nil
                    world.is_mission_control_open = false
                    return
                end
                world.is_mission_control_open = not world.is_mission_control_open
                if world.is_mission_control_open then
                    world.mission_control_openings = world.mission_control_openings + 1
                    if world.on_mission_control_open then
                        world.on_mission_control_open()
                    end
                end
            end,
            watcher = watcher_factory(),
        },
        execute = function(command)
            if command == MACOS_START_TIME_COMMAND and world.macos_start_time == false then
                return "", nil
            end
            if command == MACOS_START_TIME_COMMAND then
                return string.format(
                    "{ sec = %d, usec = 0 } Mon Oct 21 10:40:00 2024\n",
                    world.macos_start_time
                ),
                    true
            end
            if command ~= SYMBOLIC_HOTKEYS_EXPORT then
                error(
                    "the fake runs no command but the export of the shortcuts and the start of"
                        .. " macOS: "
                        .. command
                )
            end
            world.execute_calls = world.execute_calls + 1
            return SYMBOLIC_HOTKEYS_EXPORT, true
        end,
        webview = {
            usercontent = {
                new = function(name)
                    local content = { name = name }
                    function content:setCallback(callback)
                        world.webview_message_callbacks[name] = callback
                        return content
                    end
                    return content
                end,
            },
            new = function(frame)
                local view = { frame = frame, is_visible = false, page = "" }
                for _, name in ipairs({
                    "windowTitle",
                    "windowStyle",
                    "allowTextEntry",
                    "closeOnEscape",
                    "deleteOnClose",
                    "bringToFront",
                }) do
                    view[name] = function()
                        return view
                    end
                end
                function view:windowCallback(callback)
                    view.window_callback = callback
                    return view
                end
                function view:html(text)
                    view.page = text
                    return view
                end
                function view:evaluateJavaScript(script)
                    view.scripts = view.scripts or {}
                    table.insert(view.scripts, script)
                    return view
                end
                function view:show()
                    view.is_visible = true
                    world.webview = view
                    return view
                end
                function view:hswindow()
                    return nil
                end
                ---Calls the window callback with "closing", as `hs.webview:delete` does.
                function view:delete()
                    view.is_visible = false
                    if view.window_callback then
                        view.window_callback("closing", view)
                    end
                end
                return view
            end,
        },
        task = {
            ---A task of the fake lists the windows of the window server after 0.2 seconds, runs
            ---the fake of the helper of the previews, or runs the script that turns one shortcut
            ---of macOS off at once, and the fake runs no other script.
            ---The streaming callback comes before the arguments, as in Hammerspoon.
            ---The list of the window server comes in two parts, the first through the streaming
            ---callback and the rest with the exit, when the task has a streaming callback.
            ---Without one, the task gives the whole list with the exit, and never ends under
            ---`is_server_list_above_64_kib`.
            new = function(path, callback, stream_callback_or_arguments, arguments)
                local stream_callback = stream_callback_or_arguments
                if type(stream_callback_or_arguments) == "table" then
                    stream_callback, arguments = nil, stream_callback_or_arguments
                end
                local task = {}
                function task:start()
                    if path == OSASCRIPT_PATH then
                        local script = arguments[3]
                        if script:match("capture_window_previews%.js$") then
                            return start_fake_helper(task, callback, stream_callback, arguments)
                        end
                        if not script:match("list_server_windows%.js$") then
                            error("the fake runs no script of osascript but two: " .. script)
                        end
                        new_timer(0.2, function()
                            if stream_callback then
                                local split = math.floor(#SERVER_WINDOWS_OUTPUT / 2)
                                stream_callback(task, SERVER_WINDOWS_OUTPUT:sub(1, split), "")
                                callback(0, SERVER_WINDOWS_OUTPUT:sub(split + 1), "")
                            elseif not world.is_server_list_above_64_kib then
                                callback(0, SERVER_WINDOWS_OUTPUT, "")
                            end
                        end, false)
                        return task
                    end
                    local script = arguments and arguments[1] or ""
                    if not script:match("disable_macos_shortcut%.sh$") then
                        error("the fake runs no script but disable_macos_shortcut.sh: " .. script)
                    end
                    table.insert(world.tasks, { path = path, arguments = arguments })
                    if world.task_exit_code == 0 then
                        world.symbolic_hotkeys[arguments[2]] = {
                            enabled = false,
                            value = {
                                parameters = {
                                    tonumber(arguments[3]),
                                    tonumber(arguments[4]),
                                    tonumber(arguments[5]),
                                },
                            },
                        }
                    end
                    callback(world.task_exit_code, "", "")
                    return task
                end
                return task
            end,
        },
        plist = {
            readString = function(text)
                if text ~= SYMBOLIC_HOTKEYS_EXPORT then
                    return nil
                end
                return { AppleSymbolicHotKeys = world.symbolic_hotkeys }
            end,
        },
        eventtap = {
            checkKeyboardModifiers = function()
                return world.held_modifiers
            end,
            keyStroke = function(modifiers, character)
                table.insert(world.key_strokes, table.concat(modifiers, "+") .. "+" .. character)
            end,
            event = { types = { keyDown = 10, flagsChanged = 12 } },
            new = function(_, callback)
                local tap = { is_running = false, callback = callback }
                function tap:start()
                    tap.is_running = true
                    return tap
                end
                function tap:stop()
                    tap.is_running = false
                    return tap
                end
                table.insert(world.event_taps, tap)
                return tap
            end,
        },
        keycodes = {
            map = (function()
                local map = {}
                for name, code in pairs(KEY_CODES) do
                    map[name] = code
                    map[code] = name
                end
                return map
            end)(),
        },
        image = {
            imageFromAppBundle = function(bundle_id)
                world.icon_reads[bundle_id] = (world.icon_reads[bundle_id] or 0) + 1
                if world.bundle_ids_without_icon[bundle_id] then
                    return nil
                end
                return { source = "icon " .. bundle_id }
            end,
            ---Reads the data URL that the fake of the helper gives a window.
            imageFromURL = function(url)
                local window_id = url:match("^" .. DATA_URL_PREFIX:gsub("%p", "%%%0") .. "(%d+)$")
                world.clock = world.clock + world.decode_seconds
                if not window_id then
                    return nil
                end
                return { source = "blurred " .. window_id }
            end,
        },
        drawing = {
            getTextDrawingSize = function(text, style)
                return { w = #text * style.size / 2, h = style.size }
            end,
        },
        canvas = {
            windowLevels = world.window_levels,
            ---A canvas raises an error on each call after its `delete`, as a deleted canvas of
            ---Hammerspoon is no longer valid.
            new = function(frame)
                local canvas = {
                    current_frame = frame,
                    elements = {},
                    is_visible = false,
                    is_deleted = false,
                    replace_count = 0,
                }
                table.insert(world.canvases, canvas)
                function canvas:level(level)
                    canvas.window_level = level
                    return canvas
                end
                function canvas:behaviorAsLabels()
                    return canvas
                end
                function canvas:mouseCallback(callback)
                    canvas.mouse_callback = callback
                    return canvas
                end
                function canvas:canvasMouseEvents(down, up, enter_exit, move)
                    canvas.canvas_mouse_events =
                        { down = down, up = up, enter_exit = enter_exit, move = move }
                    return canvas
                end
                function canvas:frame(new_frame)
                    canvas.current_frame = new_frame
                    return canvas
                end
                function canvas:elementAttribute(index, key, value)
                    canvas.elements[index][key] = value
                    return canvas
                end
                function canvas:replaceElements(elements)
                    canvas.elements = elements
                    canvas.replace_count = canvas.replace_count + 1
                    return canvas
                end
                function canvas:show()
                    canvas.is_visible = true
                    world.overlay = canvas
                    return canvas
                end
                function canvas:delete()
                    canvas.is_visible = false
                    canvas.is_deleted = true
                end
                for name, method in pairs(canvas) do
                    if type(method) == "function" then
                        canvas[name] = function(...)
                            if canvas.is_deleted then
                                error(string.format("canvas:%s() after canvas:delete()", name), 2)
                            end
                            return method(...)
                        end
                    end
                end
                return canvas
            end,
        },
        window = {
            allWindows = list_window_objects,
            ---The windows in sight, front to back: the focused window first, then the others in the
            ---order in which they opened.
            orderedWindows = function()
                local objects = {}
                local focused = world.focused_window_id and world.windows[world.focused_window_id]
                if focused and not focused.is_minimized then
                    table.insert(objects, focused.object)
                end
                for _, window_id in ipairs(world.window_order) do
                    local window = world.windows[window_id]
                    if window ~= focused and not window.is_minimized and not window.is_unseen then
                        table.insert(objects, window.object)
                    end
                end
                return objects
            end,
            focusedWindow = function()
                local window = world.focused_window_id and world.windows[world.focused_window_id]
                return window and window.object
            end,
            get = function(window_id)
                local window = world.windows[window_id]
                return window and not window.is_unseen and window.object or nil
            end,
            filter = {
                new = function()
                    return filter_object
                end,
                windowCreated = "windowCreated",
                windowDestroyed = "windowDestroyed",
                windowMoved = "windowMoved",
                windowMinimized = "windowMinimized",
                windowUnminimized = "windowUnminimized",
                windowTitleChanged = "windowTitleChanged",
            },
        },
        application = {
            watcher = application_watcher,
            runningApplications = function()
                local bundle_ids = {}
                for bundle_id, application in pairs(world.applications) do
                    if application.is_running then
                        table.insert(bundle_ids, bundle_id)
                    end
                end
                table.sort(bundle_ids)
                local objects = {}
                for _, bundle_id in ipairs(bundle_ids) do
                    table.insert(objects, application_object(bundle_id))
                end
                return objects
            end,
            applicationForPID = function(pid)
                for bundle_id, application in pairs(world.applications) do
                    if application.pid == pid and application.is_running then
                        return application_object(bundle_id)
                    end
                end
                return nil
            end,
            applicationsForBundleID = function(bundle_id)
                if bundle_id == WINDOW_MANAGER_BUNDLE_ID then
                    return { window_manager_application }
                end
                local application = world.applications[bundle_id]
                if application and application.is_running then
                    return { application_object(bundle_id) }
                end
                return {}
            end,
            get = function(hint)
                for bundle_id, application in pairs(world.applications) do
                    if
                        (bundle_id == hint or application.name == hint) and application.is_running
                    then
                        return application_object(bundle_id)
                    end
                end
                list_window_objects()
                return nil
            end,
            frontmostApplication = function()
                local window = world.focused_window_id and world.windows[world.focused_window_id]
                return window and application_object(window.bundle_id)
            end,
            launchOrFocusByBundleID = function(bundle_id)
                local application = world.applications[bundle_id]
                if not application.is_running then
                    return hs.application.open(bundle_id) ~= nil
                end
                if application.reopen_title then
                    new_timer(0.2, function()
                        world.create_window(bundle_id, application.reopen_title)
                    end, false)
                end
                return true
            end,
            open = function(bundle_id)
                local application = world.applications[bundle_id]
                application.is_running = true
                new_timer(1, function()
                    for _, title in ipairs(application.launch_titles) do
                        world.create_window(bundle_id, title)
                    end
                end, false)
                return application_object(bundle_id)
            end,
        },
        axuielement = {
            applicationElement = function(application)
                if application == window_manager_application then
                    world.window_manager_reads = world.window_manager_reads + 1
                    if world.on_window_manager_read then
                        world.on_window_manager_read()
                    end
                end
                if application == window_manager_application and world.is_mission_control_open then
                    return mission_control_element()
                end
                return accessibility_element({}, {})
            end,
        },
        hotkey = {
            bind = function(modifiers, key, callback)
                local modifier_key = table.concat(modifiers, "+")
                local hotkey = { is_enabled = true }
                function hotkey:disable()
                    hotkey.is_enabled = false
                    table.insert(world.hotkey_events, "disable " .. modifier_key .. " " .. key)
                    return hotkey
                end
                function hotkey:enable()
                    hotkey.is_enabled = true
                    table.insert(world.hotkey_events, "enable " .. modifier_key .. " " .. key)
                    return hotkey
                end
                local by_key = modifier_key == "cmd+alt+shift" and world.hotkeys
                    or world.app_hotkeys
                function hotkey:delete()
                    if world.hotkey_by_shortcut[modifier_key .. " " .. key] == callback then
                        world.hotkey_by_shortcut[modifier_key .. " " .. key] = nil
                    end
                    if by_key[key] == callback then
                        by_key[key] = nil
                    end
                end
                world.hotkey_by_shortcut[modifier_key .. " " .. key] = callback
                by_key[key] = callback
                return hotkey
            end,
        },
        urlevent = {
            bind = function(name, callback)
                world.url_handlers[name] = callback
            end,
        },
        menubar = {
            new = function()
                local menubar = {}
                function menubar:setTitle(title)
                    world.menubar_title = title
                end
                function menubar:setTooltip(tooltip)
                    world.menubar_tooltip = tooltip
                end
                function menubar:setMenu(builder)
                    world.menu_builder = builder
                end
                return menubar
            end,
        },
        notify = {
            new = function(attributes)
                return {
                    send = function()
                        table.insert(world.notifications, attributes.informativeText)
                    end,
                }
            end,
        },
        alert = {
            show = function(text)
                table.insert(world.alerts, text)
            end,
        },
        logger = {
            new = function()
                local function record(...)
                    local parts = {}
                    for index = 1, select("#", ...) do
                        table.insert(parts, tostring(select(index, ...)))
                    end
                    table.insert(current_world.log_lines, table.concat(parts, " "))
                end
                local function record_formatted(format, ...)
                    table.insert(current_world.log_lines, string.format(format, ...))
                end
                return { i = record, f = record_formatted, w = record, e = record, d = record }
            end,
        },
        json = {
            ---Reads the output of the fake of `list_server_windows.js`: every window, in the
            ---form that the script prints.
            decode = function(text)
                if text ~= SERVER_WINDOWS_OUTPUT then
                    error("the fake decodes no JSON but the list of the windows: " .. text)
                end
                local rows = {}
                for _, window_id in ipairs(world.window_order) do
                    local window = world.windows[window_id]
                    local application = world.applications[window.bundle_id]
                    table.insert(rows, {
                        window_id = window_id,
                        pid = application.pid,
                        title = window.title,
                        x = window.frame.x,
                        y = window.frame.y,
                        w = window.frame.w,
                        h = window.frame.h,
                        is_shown = not window.is_ordered_out,
                    })
                end
                return rows
            end,
            ---The state file is `world.saved_json`, and every other file is in
            ---`world.json_files` under its path.
            encode = function()
                return "{}"
            end,
            write = function(data, path)
                if world.unwritable_paths[path] then
                    return false
                end
                if path == world.shortcuts_file_path then
                    world.json_files[path] = data
                else
                    world.saved_json = data
                end
                return true
            end,
            read = function(path)
                if path == world.shortcuts_file_path then
                    return world.json_files[path]
                end
                return world.saved_json
            end,
        },
        fs = {
            attributes = function(path)
                if path == world.shortcuts_file_path then
                    return world.json_files[path] and {} or nil
                end
                return world.saved_json and {} or nil
            end,
        },
        dialog = {
            textPrompt = function()
                return "Rename", world.prompt_answer or ""
            end,
            blockAlert = function()
                return world.alert_button or "Cancel"
            end,
        },
    }
    return world
end

return fake_hammerspoon
