local app_number_list_overlay = require("desktop_manager.macos.app_number_list_overlay")
local app_number_list_view = require("desktop_manager.core.app_number_list_view")
local app_numbers = require("desktop_manager.core.app_numbers")
local app_switcher = require("desktop_manager.macos.app_switcher")
local hidden_application_filter = require("desktop_manager.macos.hidden_application_filter")
local keyboard_modifiers = require("desktop_manager.macos.keyboard_modifiers")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local retained_timers = require("desktop_manager.macos.retained_timers")
local track_windows = require("desktop_manager.macos.track_windows")
local window_inventory = require("desktop_manager.macos.window_inventory")

---The list of numbered applications that a press of Control-Option with a number shows while the
---user holds the modifiers, and the press that brings the selected window to the front once they
---are released.
local app_number_list = {}

---What the list needs of the controller.
---@class AppNumberListContext
---@field settings Settings
---@field window_filter table an hs.window.filter
---@field window_inventory WindowInventory
---@field hidden_states HiddenStates
---@field preview_loader PreviewLoader
---@field read_numbering_profile fun(): Profile the profile whose application numbers hold
---@field list_recorded_window_ids_of_application fun(bundle_id: string): integer[]
---@field refresh_window_inventory fun() lists the windows that accessibility does not reach again,
---in the background
---@field refuse_while_busy fun(): boolean shows "Desktop Manager is still switching" while a
---switch, a restore or a press runs, and says whether it did
---@field read_switcher_context fun(): SwitcherContext the presses of the list, through the
---controller
---@field report_failures fun(failures: string[])

---The list of numbered applications that a press of their modifiers with a number opens.
---@class AppNumberListSession
---@field entries AppNumber[]
---@field applications NumberedApplication[]
---@field window_by_id table<integer, table> the hs.window of each window id in the list
---@field unreached_by_id table<integer, ServerWindow> the windows of the list that accessibility
---does not reach
---@field selection AppNumberListSelection|nil
---@field images IconsAndPreviews the icons and the previews that the list shows
---@field displays AppNumberListDisplay[] the displays from left to right, for the columns per
---display
---@field modifiers string[] the modifiers of the shortcut that opened the list, which the user
---holds
---@field overlay table|nil the hs.canvas of the list
---@field event_tap table|nil the hs.eventtap that watches the modifiers and Escape
---@field shown_at number|nil when the list showed, in seconds since the epoch
---@field last_input_at number when the last press of a number came, which holds the next preview
---back

---The windows that the list shows, as the setting for the windows of hidden applications keeps
---them.
---@class ShownWindows
---@field hidden HiddenApplications the hidden applications, as `hidden_application_filter` reads
---them
---@field filter_windows table[] the hs.window objects of the window filter that the list shows
---@field unreached_windows ServerWindow[] the windows that accessibility does not reach and that
---the list shows

---@class AppNumberList
---@field context AppNumberListContext
---@field session AppNumberListSession|nil the list while it shows
local AppNumberList = {}
AppNumberList.__index = AppNumberList

---@param context AppNumberListContext
---@return AppNumberList
function app_number_list.new(context)
    return setmetatable({ context = context }, AppNumberList)
end

---@return boolean whether the list shows
function AppNumberList:is_open()
    return self.session ~= nil
end

---@param session AppNumberListSession
---@param settings Settings
---@return AppNumberListView
local function describe_view(session, settings)
    return app_number_list_view.describe_view(
        settings.list_layout,
        session.applications,
        session.selection,
        session.displays,
        app_number_list_overlay.MAX_TITLE_LENGTH
    )
end

---@param settings Settings
---@return AppNumberListSettings the settings that the list and the search of the windows share
local function describe_list_settings(settings)
    return {
        preview_size = settings.preview_size,
        font_size = settings.list_font_size,
        sizing = settings.list_sizing,
        title_overflow = settings.title_overflow,
        title_line_count = settings.title_line_count,
    }
end

---@param settings Settings
---@return AppNumberListDisplay[] the displays in the order in which they stand from left to right
local function list_displays_from_left(settings)
    local screens = read_screens.describe_screens(settings.builtin_screen_name_patterns)
    table.sort(screens, function(first, second)
        return first.frame.x < second.frame.x
    end)
    local displays = {}
    for _, screen in ipairs(screens) do
        table.insert(displays, { screen_uuid = screen.uuid, name = screen.name })
    end
    return displays
end

---@param context AppNumberListContext
---@return ShownWindows
local function read_shown_windows(context)
    local hidden = hidden_application_filter.read_hidden_applications(
        context.settings.hidden_application_windows,
        context.hidden_states
    )
    local all_filter_windows = context.window_filter:getWindows()
    local filter_windows =
        hidden_application_filter.keep_shown_filter_windows(hidden, all_filter_windows)
    local unreached_windows = hidden_application_filter.keep_shown_unreached_windows(
        hidden,
        window_inventory.list_unreached_windows(
            context.window_inventory,
            track_windows.index_ids(all_filter_windows)
        )
    )
    return {
        hidden = hidden,
        filter_windows = filter_windows,
        unreached_windows = unreached_windows,
    }
end

---@param entries AppNumber[]
---@param shown ShownWindows
---@return NumberedApplication[] applications
---@return table<integer, table> window_by_id the hs.window of each window id in the list
local function describe_applications(entries, shown)
    local screen_uuid_by_space =
        read_desktops.index_screen_of_each_space(read_desktops.read_desktop_layout())
    local applications, window_by_id = {}, {}
    for _, entry in ipairs(entries) do
        local application, windows = app_switcher.describe_application(
            entry,
            shown.filter_windows,
            shown.unreached_windows,
            screen_uuid_by_space,
            shown.hidden
        )
        table.insert(applications, application)
        for window_id, window in pairs(windows) do
            window_by_id[window_id] = window
        end
    end
    return applications, window_by_id
end

---@param unreached_windows ServerWindow[]
---@return table<integer, ServerWindow>
local function index_unreached_by_id(unreached_windows)
    local unreached_by_id = {}
    for _, window in ipairs(unreached_windows) do
        unreached_by_id[window.window_id] = window
    end
    return unreached_by_id
end

---@param entries AppNumber[]
---@param preview_loader PreviewLoader
---@return table<string, table> the hs.image of the icon of each application, by its bundle id
local function read_app_icons(entries, preview_loader)
    local app_icons = {}
    for _, entry in ipairs(entries) do
        app_icons[entry.bundle_id] = preview_loader:read_app_icon(entry.bundle_id)
    end
    return app_icons
end

---Opens the list with the window of the number selected, or moves the selection while the list
---shows.
---A number that the active profile, or profile 0 while no profile is active, gives to no
---application passes its keys through to the application in front while the list is closed.
---@param app_number integer
---@param binding ShortcutBinding the shortcut of the number and its hs.hotkey
function AppNumberList:press(app_number, binding)
    local session = self.session
    if session then
        session.last_input_at = hs.timer.secondsSinceEpoch()
        session.selection =
            app_number_list_view.press(session.applications, session.selection, app_number)
        if session.overlay then
            app_number_list_overlay.update(
                session.overlay,
                describe_view(session, self.context.settings),
                session.images
            )
        end
        return
    end
    local entries = self.context.read_numbering_profile().app_numbers
    if not app_numbers.find_by_number(entries, app_number) then
        binding.hotkey:disable()
        hs.eventtap.keyStroke(binding.shortcut.modifiers, binding.shortcut.key, 0)
        binding.hotkey:enable()
        return
    end
    self:open(entries, app_number, binding.shortcut.modifiers)
end

---Shows the list while the user holds the modifiers, and goes to the selection when they are
---released, or at once when they were released before the event tap started.
---@param entries AppNumber[]
---@param app_number integer
---@param modifiers string[] the modifiers of the shortcut that opened the list, which the user
---holds
function AppNumberList:open(entries, app_number, modifiers)
    local shown = read_shown_windows(self.context)
    self.context.refresh_window_inventory()
    local applications, window_by_id = describe_applications(entries, shown)
    local session = {
        entries = entries,
        applications = applications,
        window_by_id = window_by_id,
        unreached_by_id = index_unreached_by_id(shown.unreached_windows),
        selection = app_number_list_view.press(applications, nil, app_number),
        images = {
            app_icons = read_app_icons(entries, self.context.preview_loader),
            previews = {},
        },
        displays = list_displays_from_left(self.context.settings),
        modifiers = modifiers,
        last_input_at = hs.timer.secondsSinceEpoch(),
    }
    self.session = session
    if not keyboard_modifiers.are_held(modifiers) then
        self:go_to_selection()
        return
    end
    self:show(session)
    if not keyboard_modifiers.are_held(modifiers) then
        self:go_to_selection()
        return
    end
    self:load_previews(session)
end

---Shows the canvas of the list and starts the event tap that watches the modifiers and Escape.
---@param session AppNumberListSession
function AppNumberList:show(session)
    session.overlay = app_number_list_overlay.show(
        describe_view(session, self.context.settings),
        session.images,
        describe_list_settings(self.context.settings)
    )
    session.shown_at = hs.timer.secondsSinceEpoch()
    local event_types = hs.eventtap.event.types
    session.event_tap = hs.eventtap
        .new({ event_types.flagsChanged, event_types.keyDown }, function(event)
            return self:handle_event(event)
        end)
        :start()
end

---Draws the preview of each window of the list in the place of the icon, as the snapshot comes.
---@param session AppNumberListSession
function AppNumberList:load_previews(session)
    local window_ids = {}
    for _, application in ipairs(session.applications) do
        for _, window in ipairs(application.windows) do
            table.insert(window_ids, window.window_id)
        end
    end
    self.context.preview_loader:load(window_ids, {
        preview_size = app_number_list_overlay.read_preview_size(session.overlay),
        shown_at = session.shown_at,
        read_last_input_at = function()
            return session.last_input_at
        end,
        is_wanted = function()
            return self.session == session
        end,
        on_image = function(window_id, image)
            if session.overlay then
                session.images.previews[window_id] = image
                app_number_list_overlay.update(
                    session.overlay,
                    describe_view(session, self.context.settings),
                    session.images
                )
            end
        end,
    })
end

---Goes to the selection when a modifier of the numbers is released, and closes the list on Escape.
---The work runs after the event tap returns, so that the tap has stopped before Mission Control
---opens to show another desktop.
---@param event table an hs.eventtap.event
---@return boolean whether the event stops here
function AppNumberList:handle_event(event)
    local event_types = hs.eventtap.event.types
    if event:getType() == event_types.keyDown then
        if event:getKeyCode() == hs.keycodes.map.escape then
            retained_timers.defer(function()
                self:close()
            end)
            return true
        end
        return false
    end
    if not keyboard_modifiers.are_all_in(event:getFlags(), self.session.modifiers) then
        retained_timers.defer(function()
            self:go_to_selection()
        end)
    end
    return false
end

---@return AppNumberListSession|nil the session that was open
function AppNumberList:close()
    local session = self.session
    if not session then
        return nil
    end
    self.session = nil
    if session.event_tap then
        session.event_tap:stop()
    end
    if session.overlay then
        app_number_list_overlay.hide(session.overlay)
    end
    return session
end

---Closes the list and brings the selected window to the front, reaches it on its desktop, or
---unhides its application.
function AppNumberList:go_to_selection()
    local context = self.context
    local session = self:close()
    if not session or not session.selection or context.refuse_while_busy() then
        return
    end
    local entry = app_numbers.find_by_number(session.entries, session.selection.number)
    local window_id =
        app_number_list_view.find_selected_window_id(session.applications, session.selection)
    local function report(error_message)
        if error_message then
            context.report_failures({ error_message })
        end
    end
    local unreached = window_id and session.unreached_by_id[window_id]
    if unreached then
        app_switcher.reach_window(unreached, context.read_switcher_context(), report)
        return
    end
    local selected_number = session.selection.number
    if app_number_list_view.find_application(session.applications, selected_number).is_hidden then
        app_switcher.unhide_application(
            entry,
            context.list_recorded_window_ids_of_application(entry.bundle_id),
            context.read_switcher_context(),
            report
        )
        return
    end
    app_switcher.switch_to_selection(
        entry,
        window_id and session.window_by_id[window_id],
        context.list_recorded_window_ids_of_application(entry.bundle_id),
        context.read_switcher_context(),
        report
    )
end

return app_number_list
