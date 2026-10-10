---A fake of the parts of Hammerspoon that the tool calls, for tests of the controller flow.
---The fake models screens, desktops, windows and applications, and assumes that macOS
---unminimizes a window onto the active desktop of its screen.
---It checks the logic of the tool, and says nothing about what macOS 27 really does.
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

---@class FakeWorldSpec
---@field screens { id: integer, uuid: string, name: string, frame: Rect }[]
---@field displays { uuid: string, space_ids: integer[], active_space_id: integer }[]
---@field applications FakeApplicationSpec[]
---@field windows FakeWindowSpec[]

local USER_SPACE_TYPE = 0

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
        held_modifiers = {},
        key_strokes = {},
        alerts = {},
        notifications = {},
        hotkeys = {},
        url_handlers = {},
        filter_callbacks = {},
        application_watchers = {},
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
            local was_hidden = application.is_hidden
            application.is_hidden = false
            if was_hidden then
                for _, watcher in ipairs(world.application_watchers) do
                    watcher(application.name, hs.application.watcher.unhidden, object)
                end
            end
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
            window.is_minimized = true
            return object
        end
        function object:unminimize()
            window.is_minimized = false
            window.space_id = active_space_at(window.frame)
            return object
        end
        function object:frame()
            local frame = window.frame
            return { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
        end
        function object:setFrame(rect)
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
        }
    end
    for _, window_spec in ipairs(spec.windows) do
        add_window(window_spec)
    end

    local function emit_filter_event(event, window)
        local callback = world.filter_callbacks[event]
        if callback then
            callback(window.object, world.applications[window.bundle_id].name, event)
        end
    end

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

    local function new_timer(seconds, callback, is_repeating)
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

    local filter_object = {}
    function filter_object:setDefaultFilter()
        return filter_object
    end
    function filter_object:getWindows()
        local windows = {}
        for _, window_id in ipairs(world.window_order) do
            table.insert(windows, world.windows[window_id].object)
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
            watcher = watcher_factory(),
        },
        spaces = {
            data_managedDisplaySpaces = managed_displays,
            focusedSpace = function()
                return world.displays[1].active_space_id
            end,
            windowSpaces = function(window_id)
                local window = world.windows[window_id]
                if not window or window.is_minimized then
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
        },
        window = {
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
            get = function(bundle_id)
                local application = world.applications[bundle_id]
                if application and application.is_running then
                    return application_object(bundle_id)
                end
                return nil
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
            bind = function(_, key, callback)
                world.hotkeys[key] = callback
                return {}
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
                return { i = ignore, w = ignore, e = ignore, d = ignore }
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
