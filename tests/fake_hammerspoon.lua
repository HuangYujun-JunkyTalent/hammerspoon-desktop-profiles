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
---Hammerspoon started, which accessibility does not reach until its desktop shows

---@class FakeApplicationSpec
---@field bundle_id string
---@field name string
---@field is_running boolean
---@field launch_titles string[]|nil the titles of the windows that a launch opens
---@field new_window_title string|nil the title of the window that the menu item New Window opens
---@field reopen_title string|nil the title of the window that a reopen opens
---A test sets these fields on `world.applications[bundle_id]` after the install:
---`is_dropped_by_filter_while_hidden` makes the window filter leave out the windows of the hidden
---application, as Hammerspoon does with a window that reports another subrole while hidden.
---`ignores_unhide` makes an unhide leave the application hidden.

---@class FakeWorldSpec
---@field screens { id: integer, uuid: string, name: string, frame: Rect }[]
---@field displays { uuid: string, space_ids: integer[], active_space_id: integer }[]
---@field applications FakeApplicationSpec[]
---@field windows FakeWindowSpec[]

local USER_SPACE_TYPE = 0
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
local FIRST_PID = 500
local WINDOW_MANAGER_BUNDLE_ID = "com.apple.WindowManager"

---@param spec FakeWorldSpec
---@return table world
---The shortcuts "Switch to Desktop 1" to "Switch to Desktop N" as Control-1 to Control-9 and
---Control-0, in the form of `AppleSymbolicHotKeys` of macOS.
---@param highest_number integer 9, as on the machine of the user, or 10, as the script of the
---repository turns them on
---@return table
local function all_desktop_shortcuts(highest_number)
    local key_codes = { 18, 19, 20, 21, 23, 22, 26, 28, 25, 29 }
    local hotkeys = {}
    for number = 1, highest_number do
        local key_code = key_codes[number]
        hotkeys[tostring(117 + number)] = {
            enabled = true,
            value = { parameters = { 65535, key_code, 262144 }, type = "standard" },
        }
    end
    return hotkeys
end

local SYMBOLIC_HOTKEYS_EXPORT = "defaults export com.apple.symbolichotkeys -"

function fake_hammerspoon.install(spec)
    local world = {
        clock = 0,
        timers = {},
        screens = spec.screens,
        displays = spec.displays,
        applications = {},
        windows = {},
        window_order = {},
        window_operations = {},
        held_modifiers = {},
        key_strokes = {},
        symbolic_hotkeys = all_desktop_shortcuts(9),
        tasks = {},
        task_exit_code = 0,
        alerts = {},
        notifications = {},
        hotkeys = {},
        app_hotkeys = {},
        hotkey_by_shortcut = {},
        hotkey_events = {},
        event_taps = {},
        snapshot_count = 0,
        rendered_sizes = {},
        snapshot_seconds = 0.05,
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
        shortcuts_file_path = "/fake/keyboard-shortcuts.json",
        next_window_id = 1000,
        next_space_id = 2000,
        is_mission_control_open = false,
        mission_control_actions = {},
        window_list_runs = 0,
    }

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

    ---An accessibility element whose attributes may be functions, read at each call, and whose
    ---actions are functions.
    ---@param attributes table<string, any>
    ---@param actions table<string, fun()>
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
                action()
                return true
            end,
        }
    end

    local window_manager_application = {}
    function window_manager_application:bundleID()
        return WINDOW_MANAGER_BUNDLE_ID
    end

    ---@param display table a display of the world
    ---@param space_id integer
    ---@return table the thumbnail of a desktop in the list of Mission Control
    local function desktop_thumbnail(display, space_id)
        return accessibility_element({ AXIdentifier = "mc.space" }, {
            AXRemoveDesktop = function()
                for index = #display.space_ids, 1, -1 do
                    if display.space_ids[index] == space_id then
                        table.remove(display.space_ids, index)
                    end
                end
                for _, window in pairs(world.windows) do
                    if window.space_id == space_id then
                        window.space_id = display.space_ids[1]
                    end
                end
                table.insert(world.mission_control_actions, "remove " .. space_id)
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
                end,
            })
            local spaces_list = accessibility_element({
                AXIdentifier = "mc.spaces.list",
                AXChildren = function()
                    local thumbnails = {}
                    for _, space_id in ipairs(display.space_ids) do
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
            return 1
        end
        function object:isHidden()
            return application.is_hidden
        end
        function object:hide()
            application.is_hidden = true
            return true
        end
        function object:unhide()
            if application.ignores_unhide then
                return false
            end
            local was_hidden = application.is_hidden
            application.is_hidden = false
            if was_hidden then
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
        function object:allWindows()
            local windows = {}
            for _, window_id in ipairs(world.window_order) do
                local window = world.windows[window_id]
                if window.bundle_id == bundle_id and not window.is_unseen then
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
            world.focused_window_id = window.id
            table.insert(world.window_operations, "focus " .. window.id)
            return object
        end
        function object:isStandard()
            return window.is_standard ~= false
        end
        function object:title()
            return window.title
        end
        function object:application()
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

    ---The texts of the list on the screen, each after the mark of the rectangle behind it, such as
    ---"selection" or "match-strong", or after "faded" for a faded text, or after "plain".
    ---@return string[]|nil
    function world.read_overlay_marks()
        if not world.overlay or not world.overlay.is_visible then
            return nil
        end
        local texts, mark = {}, nil
        for _, element in ipairs(world.overlay.elements) do
            if element.type == "rectangle" and element.frame and not element.trackMouseByBounds then
                mark = element.id
            elseif element.type == "text" then
                table.insert(texts, (mark or element.id or "plain") .. " " .. element.text)
                mark = nil
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

    ---Sends a message of the page of the webview, as its script posts one.
    ---@param body table
    function world.post_to_webview(body)
        world.webview_message_callback({ name = "appPool", body = body })
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
            world.clock = next_timer.due
            if next_timer.is_repeating then
                next_timer.due = world.clock + math.max(next_timer.interval, 0.001)
            else
                next_timer.is_running = false
            end
            next_timer.callback()
        end
        world.clock = target
    end

    local function managed_displays()
        local displays = {}
        for _, display in ipairs(world.displays) do
            local spaces = {}
            for _, space_id in ipairs(display.space_ids) do
                table.insert(spaces, { ManagedSpaceID = space_id, type = USER_SPACE_TYPE })
            end
            table.insert(displays, {
                ["Display Identifier"] = display.uuid,
                ["Current Space"] = { ManagedSpaceID = display.active_space_id },
                Spaces = spaces,
            })
        end
        return displays
    end

    local function switch_by_shortcut(number)
        local count = 0
        for _, display in ipairs(world.displays) do
            for _, space_id in ipairs(display.space_ids) do
                count = count + 1
                if count == number then
                    display.active_space_id = space_id
                    for _, window in pairs(world.windows) do
                        if window.space_id == space_id then
                            window.is_unseen = false
                        end
                    end
                end
            end
        end
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
        unhidden = "unhidden",
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
        local windows = {}
        for _, window_id in ipairs(world.window_order) do
            if not world.windows[window_id].is_unseen then
                table.insert(windows, world.windows[window_id].object)
            end
        end
        return windows
    end

    local filter_object = {}
    function filter_object:setDefaultFilter()
        return filter_object
    end
    function filter_object:getWindows()
        local windows = {}
        for _, window_id in ipairs(world.window_order) do
            local window = world.windows[window_id]
            local application = world.applications[window.bundle_id]
            if
                not window.is_unseen
                and not (application.is_hidden and application.is_dropped_by_filter_while_hidden)
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

    _G.hs = {
        configdir = "/fake/.hammerspoon",
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
                return world.displays[1].active_space_id
            end,
            windowSpaces = function(window_id)
                local window = world.windows[window_id]
                if not window then
                    return {}
                end
                return { window.space_id }
            end,
            windowsForSpace = function(space_id)
                local window_ids = {}
                for _, window_id in ipairs(world.window_order) do
                    local window = world.windows[window_id]
                    if window.space_id == space_id and not window.is_minimized then
                        table.insert(window_ids, window_id)
                    end
                end
                return window_ids
            end,
            toggleMissionControl = function()
                world.is_mission_control_open = not world.is_mission_control_open
            end,
            watcher = watcher_factory(),
        },
        execute = function(command)
            if command ~= SYMBOLIC_HOTKEYS_EXPORT then
                error("the fake runs no command but the export of the shortcuts: " .. command)
            end
            return SYMBOLIC_HOTKEYS_EXPORT, true
        end,
        webview = {
            usercontent = {
                new = function(name)
                    local content = { name = name }
                    function content:setCallback(callback)
                        world.webview_message_callback = callback
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
                function view:delete()
                    view.is_visible = false
                end
                return view
            end,
        },
        task = {
            ---A task of the fake lists the windows of the window server after 0.2 seconds, or
            ---runs the script that turns on the desktop shortcuts at once.
            new = function(path, callback, arguments)
                local task = {}
                function task:start()
                    if path == OSASCRIPT_PATH then
                        world.window_list_runs = world.window_list_runs + 1
                        new_timer(0.2, function()
                            callback(0, SERVER_WINDOWS_OUTPUT, "")
                        end, false)
                        return task
                    end
                    table.insert(world.tasks, { path = path, arguments = arguments })
                    local script = arguments and arguments[1] or ""
                    if
                        world.task_exit_code == 0 and script:match("disable_macos_shortcut%.sh$")
                    then
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
                    elseif world.task_exit_code == 0 then
                        world.symbolic_hotkeys = all_desktop_shortcuts(10)
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
                if #modifiers == 1 and modifiers[1] == "ctrl" and tonumber(character) then
                    switch_by_shortcut(character == "0" and 10 or tonumber(character))
                end
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
                return { source = "icon " .. bundle_id }
            end,
        },
        drawing = {
            getTextDrawingSize = function(text, style)
                return { w = #text * style.size / 2, h = style.size }
            end,
        },
        canvas = {
            windowLevels = { overlay = 102 },
            new = function(frame)
                local canvas = { current_frame = frame, elements = {}, is_visible = false }
                table.insert(world.canvases, canvas)
                function canvas:level()
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
                    return canvas
                end
                function canvas:show()
                    canvas.is_visible = true
                    world.overlay = canvas
                    return canvas
                end
                function canvas:delete()
                    canvas.is_visible = false
                end
                return canvas
            end,
        },
        window = {
            allWindows = list_window_objects,
            snapshotForID = function(window_id)
                world.snapshot_count = world.snapshot_count + 1
                world.clock = world.clock + world.snapshot_seconds
                local window = world.windows[window_id]
                if not window or window.is_minimized then
                    return nil
                end
                return {
                    size = function()
                        return { w = 1200, h = 600 }
                    end,
                    bitmapRepresentation = function(_, size)
                        world.rendered_sizes[window_id] = size
                        return { source = "blurred " .. window_id }
                    end,
                }
            end,
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
                function menubar:setTooltip() end
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
                local function ignore() end
                return { i = ignore, f = ignore, w = ignore, e = ignore, d = ignore }
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
                    table.insert(rows, {
                        window_id = window_id,
                        pid = world.applications[window.bundle_id].pid,
                        title = window.title,
                        x = window.frame.x,
                        y = window.frame.y,
                        w = window.frame.w,
                        h = window.frame.h,
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
