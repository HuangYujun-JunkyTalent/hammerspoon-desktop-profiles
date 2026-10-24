local app_switcher = require("desktop_manager.macos.app_switcher")
local preview_pacing = require("desktop_manager.core.preview_pacing")
local retained_timers = require("desktop_manager.macos.retained_timers")
local search_opening_log = require("desktop_manager.core.search_opening_log")
local search_overlay = require("desktop_manager.macos.search_overlay")
local track_windows = require("desktop_manager.macos.track_windows")
local window_search = require("desktop_manager.core.window_search")

---The panel of the search of the windows: every window, the windows that accessibility does not
---reach included, with the applications in a row under the previews.
---An event tap takes the keys while the panel shows, so the application in front receives none,
---and the mouse acts on the previews and the applications.
local search_windows = {}

---What the panel needs from the controller.
---@class SearchContext
---@field filter_windows table[] the hs.window objects that accessibility reaches and the setting
---hidden_application_windows shows: the windows of the window filter, the most recently focused
---first, and the windows of hidden applications that the filter leaves out
---@field unreached_windows ServerWindow[] the windows that accessibility does not reach, as the
---last refresh found them
---@field refresh_unreached_windows fun(on_done: fun(windows: ServerWindow[],
---update_started_at: number)) lists them again, and gives when the new list began to update
---@field app_numbers AppNumber[] the numbers of the numbering profile, which the panel shows
---@field overlay_settings SearchOverlaySettings
---@field switcher SwitcherContext what brings the selected window to the front
---@field preview_loader PreviewLoader the icons and the previews of the list and the search
---@field on_closed fun()
---@field report_failures fun(messages: string[])
---@field opened_at number when the shortcut asked for the panel, in seconds since the epoch
---@field log table the hs.logger that takes the line of the opening when the panel closes

---@class SearchPanel
---@field search WindowSearch
---@field window_by_id table<integer, table> the hs.window of each window that accessibility reaches
---@field unreached_by_id table<integer, ServerWindow>
---@field images IconsAndPreviews
---@field requested_preview_ids table<integer, boolean> the windows whose previews were asked for
---@field overlay SearchOverlay
---@field event_tap table an hs.eventtap
---@field context SearchContext
---@field is_open boolean
---@field is_redraw_due boolean whether a redraw waits for the events that came at once
---@field times SearchOpeningTimes what happened since the opening, for the console
---@field shown_at number when the panel showed, in seconds since the epoch
---@field last_input_at number|nil when the last key, click or hover came, which holds the next
---preview back
---@field preview_queue PreviewQueue the snapshots of the windows of the panel

---The windows of the search, the most recently focused first, and the windows that accessibility
---does not reach after them.
---@param filter_windows table[]
---@param unreached_windows ServerWindow[]
---@return SearchEntry[] entries
---@return table<integer, table> window_by_id
---@return table<integer, ServerWindow> unreached_by_id
function search_windows.list_entries(filter_windows, unreached_windows)
    local entries, window_by_id, unreached_by_id = {}, {}, {}
    for _, window in ipairs(filter_windows) do
        local window_id = window:id()
        if window_id and window_id > 0 and not window_by_id[window_id] then
            window_by_id[window_id] = window
            local bundle_id, app_name = track_windows.identify_application(window:application())
            table.insert(entries, {
                window_id = window_id,
                title = window:title() or "",
                bundle_id = bundle_id,
                app_name = app_name,
            })
        end
    end
    for _, window in ipairs(unreached_windows) do
        if not window_by_id[window.window_id] and not unreached_by_id[window.window_id] then
            unreached_by_id[window.window_id] = window
            table.insert(entries, {
                window_id = window.window_id,
                title = window.title,
                bundle_id = window.bundle_id,
                app_name = window.app_name,
            })
        end
    end
    return entries, window_by_id, unreached_by_id
end

---@param filter_windows table[] the most recently focused first
---@return integer|nil the window that had the focus before the focused one, which Return then
---reaches at once, as Command-Tab reaches the application before
local function find_previous_window_id(filter_windows)
    local focused = hs.window.focusedWindow()
    local focused_id = focused and focused:id()
    for _, window in ipairs(filter_windows) do
        local window_id = window:id()
        if window_id and window_id > 0 and window_id ~= focused_id then
            return window_id
        end
    end
    return focused_id
end

---@param panel SearchPanel
local function redraw(panel)
    panel.is_redraw_due = false
    if panel.is_open then
        search_overlay.update(
            panel.overlay,
            window_search.describe_view(panel.search),
            panel.images
        )
    end
end

---Takes the new state of the search at once, and draws the panel once the events that came at
---once have all arrived.
---@param panel SearchPanel
---@param search WindowSearch
local function show_search(panel, search)
    if search == panel.search then
        return
    end
    panel.search = search
    if not panel.is_redraw_due then
        panel.is_redraw_due = true
        retained_timers.defer(function()
            redraw(panel)
        end)
    end
end

---@param panel SearchPanel
---@return number the seconds since the opening
local function measure_since_opening(panel)
    return hs.timer.secondsSinceEpoch() - panel.context.opened_at
end

---Closes the panel and writes the line of its opening to the console.
---@param panel SearchPanel
function search_windows.close(panel)
    if not panel.is_open then
        return
    end
    panel.is_open = false
    panel.event_tap:stop()
    search_overlay.hide(panel.overlay)
    panel.context.log.i(search_opening_log.describe(panel.times))
    panel.context.on_closed()
end

---Closes the panel and brings the selected window to the front, which shows its desktop first.
---Without a selection, as when nothing matches, the panel stays.
---While a switch, a restore or a press runs, the panel closes with the alert of the refusal.
---@param panel SearchPanel
local function go_to_selection(panel)
    local window_id = window_search.find_selected_window_id(panel.search)
    local window = window_id and panel.window_by_id[window_id]
    local unreached = window_id and panel.unreached_by_id[window_id]
    if not window and not unreached then
        return
    end
    search_windows.close(panel)
    if panel.context.switcher.refuse_while_busy() then
        return
    end
    local function report(error_message)
        if error_message then
            panel.context.report_failures({ error_message })
        end
    end
    if window then
        app_switcher.bring_to_front(window, panel.context.switcher, report)
        return
    end
    app_switcher.reach_window(unreached, panel.context.switcher, report)
end

---What each key does in the panel, by its name in hs.keycodes.map.
---Return and Escape act after the event tap returns, so that the tap has stopped before Mission
---Control opens to show another desktop.
local KEY_ACTIONS = {
    escape = function(panel)
        retained_timers.defer(function()
            search_windows.close(panel)
        end)
    end,
    ["return"] = function(panel)
        retained_timers.defer(function()
            go_to_selection(panel)
        end)
    end,
    delete = function(panel, flags)
        if flags.cmd or flags.alt then
            show_search(panel, window_search.clear_text(panel.search))
        else
            show_search(panel, window_search.delete_last_character(panel.search))
        end
    end,
    tab = function(panel, flags)
        if flags.shift then
            show_search(panel, window_search.select_previous(panel.search))
        else
            show_search(panel, window_search.select_next(panel.search))
        end
    end,
}
KEY_ACTIONS.padenter = KEY_ACTIONS["return"]
for _, direction in ipairs({
    window_search.LEFT,
    window_search.RIGHT,
    window_search.UP,
    window_search.DOWN,
}) do
    KEY_ACTIONS[direction] = function(panel)
        show_search(
            panel,
            window_search.move_in_grid(panel.search, panel.overlay.column_count, direction)
        )
    end
end

---`hs.eventtap.event:timestamp()` and `hs.timer.absoluteTime()` count nanoseconds on one clock.
local NANOSECONDS_PER_SECOND = 1e9

---macOS gives the arrows, the function keys and keys such as Home characters of this range.
local FIRST_FUNCTION_KEY_CODE_POINT = 0xF700
local LAST_FUNCTION_KEY_CODE_POINT = 0xF8FF

---@param characters string|nil
---@return boolean whether the characters can stand in the text of the search, as no control
---character and no character of a function key can
local function is_typeable(characters)
    if characters == nil or characters == "" or characters:find("%c") then
        return false
    end
    local is_valid, is_typeable_text = pcall(function()
        for _, code_point in utf8.codes(characters) do
            if
                code_point >= FIRST_FUNCTION_KEY_CODE_POINT
                and code_point <= LAST_FUNCTION_KEY_CODE_POINT
            then
                return false
            end
        end
        return true
    end)
    return is_valid and is_typeable_text
end

---Counts the key, and keeps the longest time from a key to the search.
---A key that a program made carries the timestamp 0, which gives no wait.
---@param panel SearchPanel
---@param event table an hs.eventtap.event
local function time_key(panel, event)
    panel.times.key_count = panel.times.key_count + 1
    local timestamp = event:timestamp()
    if timestamp > 0 then
        local wait_seconds = (hs.timer.absoluteTime() - timestamp) / NANOSECONDS_PER_SECOND
        panel.times.longest_key_wait_seconds =
            math.max(panel.times.longest_key_wait_seconds or 0, wait_seconds)
    end
end

---Takes every key while the panel shows: the keys of KEY_ACTIONS act, a character without Command
---or Control goes into the search, and the other keys do nothing.
---@param panel SearchPanel
---@param event table an hs.eventtap.event
---@return boolean that the event stops here
local function handle_key(panel, event)
    panel.last_input_at = hs.timer.secondsSinceEpoch()
    time_key(panel, event)
    local flags = event:getFlags()
    local action = KEY_ACTIONS[hs.keycodes.map[event:getKeyCode()]]
    if action then
        action(panel, flags)
        return true
    end
    local characters = event:getCharacters()
    if not flags.cmd and not flags.ctrl and is_typeable(characters) then
        show_search(panel, window_search.type_text(panel.search, characters))
    end
    return true
end

---Hovering over an application shows its windows, a click chooses it, hovering over a window
---selects it and a click brings it to the front.
---Leaving the panel shows the matches again, unless a click chose an application.
---@param panel SearchPanel
---@param message string
---@param id string
local function handle_mouse(panel, message, id)
    panel.last_input_at = hs.timer.secondsSinceEpoch()
    local bundle_id = id:match("^application:(.+)$")
    local window_id = math.tointeger(tonumber(id:match("^window:(%d+)$")))
    if message == "mouseEnter" and bundle_id then
        show_search(panel, window_search.hover_application(panel.search, bundle_id))
    elseif message == "mouseEnter" and window_id then
        show_search(panel, window_search.select_window(panel.search, window_id))
    elseif message == "mouseExit" and id == "_canvas_" then
        show_search(panel, window_search.hover_application(panel.search, nil))
    elseif message == "mouseUp" and bundle_id then
        show_search(panel, window_search.choose_application(panel.search, bundle_id))
    elseif message == "mouseUp" and window_id then
        panel.search = window_search.select_window(panel.search, window_id)
        retained_timers.defer(function()
            go_to_selection(panel)
        end)
    end
end

---Reads the icon of each application of the entries that the panel lacks.
---@param panel SearchPanel
---@param entries SearchEntry[]
local function read_missing_icons(panel, entries)
    local app_icons = panel.images.app_icons
    for _, entry in ipairs(entries) do
        if not app_icons[entry.bundle_id] then
            app_icons[entry.bundle_id] = panel.context.preview_loader:read_app_icon(entry.bundle_id)
        end
    end
end

---@param panel SearchPanel
---@param entries SearchEntry[]
---@return integer[] the windows of the entries whose previews the panel has not asked for yet
local function list_new_preview_ids(panel, entries)
    local window_ids = {}
    for _, entry in ipairs(entries) do
        if not panel.requested_preview_ids[entry.window_id] then
            panel.requested_preview_ids[entry.window_id] = true
            table.insert(window_ids, entry.window_id)
        end
    end
    panel.times.requested_preview_count = panel.times.requested_preview_count + #window_ids
    return window_ids
end

---Starts the queue of the previews of the panel with the entries that it shows.
---@param panel SearchPanel
---@param entries SearchEntry[]
local function load_previews(panel, entries)
    local times = panel.times
    panel.preview_queue = panel.context.preview_loader:load(list_new_preview_ids(panel, entries), {
        preview_size = search_overlay.read_preview_size(panel.overlay),
        shown_at = panel.shown_at,
        read_last_input_at = function()
            return panel.last_input_at
        end,
        is_wanted = function()
            return panel.is_open
        end,
        on_image = function(window_id, image)
            panel.images.previews[window_id] = image
            redraw(panel)
            times.preview_count = times.preview_count + 1
            times.first_preview_after = times.first_preview_after or measure_since_opening(panel)
            times.last_preview_after = measure_since_opening(panel)
        end,
        on_preview_taken = function(_, blocking_seconds)
            times.preview_blocking_seconds = times.preview_blocking_seconds + blocking_seconds
            times.longest_preview_blocking_seconds =
                math.max(times.longest_preview_blocking_seconds, blocking_seconds)
        end,
    })
end

---Takes the windows that a new list of the window server holds.
---@param panel SearchPanel
---@param unreached_windows ServerWindow[]
local function add_unreached_windows(panel, unreached_windows)
    if not panel.is_open then
        return
    end
    local entries, window_by_id, unreached_by_id =
        search_windows.list_entries(panel.context.filter_windows, unreached_windows)
    panel.window_by_id, panel.unreached_by_id = window_by_id, unreached_by_id
    read_missing_icons(panel, entries)
    show_search(panel, window_search.with_entries(panel.search, entries))
    panel.preview_queue:add(list_new_preview_ids(panel, entries))
end

---Shows the panel with the window before the focused one selected, loads the previews, and adds
---the windows of a new list of the window server when it comes.
---The new list starts once the panel has had the time to draw, because the start of its process
---holds the main thread for a few milliseconds.
---@param context SearchContext
---@return SearchPanel
function search_windows.open(context)
    local entries, window_by_id, unreached_by_id =
        search_windows.list_entries(context.filter_windows, context.unreached_windows)
    local number_by_bundle_id = {}
    for _, entry in ipairs(context.app_numbers) do
        number_by_bundle_id[entry.bundle_id] = entry.number
    end
    local panel = {
        search = window_search.start(
            entries,
            number_by_bundle_id,
            find_previous_window_id(context.filter_windows)
        ),
        window_by_id = window_by_id,
        unreached_by_id = unreached_by_id,
        images = { app_icons = {}, previews = {} },
        requested_preview_ids = {},
        context = context,
        is_open = true,
        is_redraw_due = false,
        times = {
            window_count = #entries,
            shown_after = 0,
            preview_count = 0,
            requested_preview_count = 0,
            preview_blocking_seconds = 0,
            longest_preview_blocking_seconds = 0,
            key_count = 0,
        },
    }
    read_missing_icons(panel, entries)
    panel.overlay = search_overlay.show(
        window_search.describe_view(panel.search),
        panel.images,
        context.overlay_settings,
        function(message, id)
            handle_mouse(panel, message, id)
        end
    )
    panel.shown_at = hs.timer.secondsSinceEpoch()
    panel.event_tap = hs.eventtap
        .new({ hs.eventtap.event.types.keyDown }, function(event)
            return handle_key(panel, event)
        end)
        :start()
    load_previews(panel, entries)
    retained_timers.after(preview_pacing.AFTER_DRAWING_SECONDS, function()
        context.refresh_unreached_windows(function(unreached_windows, update_started_at)
            add_unreached_windows(panel, unreached_windows)
            panel.times.server_list_after = update_started_at - context.opened_at
            panel.times.server_list_blocking_seconds = hs.timer.secondsSinceEpoch()
                - update_started_at
        end)
    end)
    panel.times.shown_after = measure_since_opening(panel)
    return panel
end

return search_windows
