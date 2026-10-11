---A fake of the parts of Hammerspoon that the tool calls, for tests of the controller flow.
---The fake models screens, desktops, windows and applications.
---It checks the logic of the tool, and says nothing about what macOS 27 really does.
---A minimized window keeps its desktop, as `hs.spaces.windowSpaces` showed on macOS 27.0.1, and an
---unminimize puts the window back on that desktop, as macOS 27.0.1 does.
local fake_hammerspoon = {}

---@class FakeWindowSpec
---@field id integer
---@field bundle_id string
---@field title string
---@field space_id integer
---@field frame Rect

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

---@param spec FakeWorldSpec
---@return table world
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
        alerts = {},
        notifications = {},
        hotkeys = {},
        app_hotkeys = {},
        hotkey_events = {},
        event_taps = {},
        snapshot_count = 0,
        rendered_sizes = {},
        snapshot_seconds = 0.05,
        overlay = nil,
        focused_window_id = nil,
        url_handlers = {},
        filter_callbacks = {},
        application_watchers = {},
        screen_watchers = {},
        menu_selections = {},
        saved_json = nil,
        next_window_id = 1000,
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
        function object:fromUnitRect(unit)
            return {
                x = screen.frame.x + unit.x * screen.frame.w,
                y = screen.frame.y + unit.y * screen.frame.h,
                w = unit.w * screen.frame.w,
                h = unit.h * screen.frame.h,
            }
        end
        table.insert(screen_objects, object)
    end

    local new_timer

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
                if window.bundle_id == bundle_id then
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
            return true
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

    for _, application in ipairs(spec.applications) do
        world.applications[application.bundle_id] = {
            name = application.name,
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

    function world.press_escape()
        send_to_event_taps({
            getType = function()
                return 10
            end,
            getKeyCode = function()
                return ESCAPE_KEY_CODE
            end,
        })
    end

    ---The texts of the list on the screen, with the selected line marked by ">".
    ---@return string[]|nil
    function world.read_overlay()
        if not world.overlay or not world.overlay.is_visible then
            return nil
        end
        local texts, is_next_selected = {}, false
        for _, element in ipairs(world.overlay.elements) do
            if element.type == "rectangle" and element.frame then
                is_next_selected = true
            elseif element.type == "text" then
                table.insert(texts, (is_next_selected and ">" or " ") .. element.text)
                is_next_selected = false
            end
        end
        return texts
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
            table.insert(windows, world.windows[window_id].object)
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
            if not (application.is_hidden and application.is_dropped_by_filter_while_hidden) then
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
            toggleMissionControl = function() end,
            watcher = watcher_factory(),
        },
        eventtap = {
            checkKeyboardModifiers = function()
                return world.held_modifiers
            end,
            keyStroke = function(modifiers, character)
                table.insert(world.key_strokes, table.concat(modifiers, "+") .. "+" .. character)
                if #modifiers == 1 and modifiers[1] == "ctrl" and tonumber(character) then
                    switch_by_shortcut(tonumber(character))
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
        keycodes = { map = { escape = ESCAPE_KEY_CODE } },
        image = {
            imageFromAppBundle = function(bundle_id)
                return { source = "icon " .. bundle_id }
            end,
        },
        canvas = {
            windowLevels = { overlay = 102 },
            new = function(frame)
                local canvas = { current_frame = frame, elements = {}, is_visible = false }
                function canvas:level()
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
            focusedWindow = function()
                local window = world.focused_window_id and world.windows[world.focused_window_id]
                return window and window.object
            end,
            get = function(window_id)
                local window = world.windows[window_id]
                return window and window.object
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
            applicationsForBundleID = function(bundle_id)
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
            applicationElement = function()
                return {
                    attributeValue = function()
                        return nil
                    end,
                }
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
                if modifier_key == "cmd+alt+shift" then
                    world.hotkeys[key] = callback
                else
                    world.app_hotkeys[key] = callback
                end
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
            write = function(data)
                world.saved_json = data
                return true
            end,
            read = function()
                return world.saved_json
            end,
        },
        fs = {
            attributes = function()
                return world.saved_json and {} or nil
            end,
        },
        dialog = {
            textPrompt = function()
                return "Rename", world.prompt_answer or ""
            end,
        },
    }
    return world
end

return fake_hammerspoon
