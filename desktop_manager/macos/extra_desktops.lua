local app_pool = require("desktop_manager.core.app_pool")
local busy_message = require("desktop_manager.macos.busy_message")
local concatenate_lists = require("desktop_manager.core.concatenate_lists")
local desktop_counts = require("desktop_manager.core.desktop_counts")
local locate_desktops = require("desktop_manager.core.locate_desktops")
local mission_control_desktops = require("desktop_manager.macos.mission_control_desktops")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local read_desktops = require("desktop_manager.macos.read_desktops")
local read_screens = require("desktop_manager.macos.read_screens")
local track_windows = require("desktop_manager.macos.track_windows")
local window_inventory = require("desktop_manager.macos.window_inventory")

---Shows desktops of the screens through Mission Control, removes the empty desktops beyond the
---number of each display, and gives the focus back to the screen of the focus, for a switch and a
---restore.
---The desktops to show are the recorded desktops, and desktop 1 of a screen in full screen whose
---record names no desktop shown.
local extra_desktops = {}

---@class ExtraDesktopsContext
---@field timing Timing
---@field log table an hs.logger
---@field read_monitor_configuration fun(): MonitorConfiguration
---@field known_windows KnownWindows
---@field window_inventory WindowInventory
---@field read_app_pool fun(): AppPool the pool of the managed applications now
---@field list_filter_window_ids fun(): table<integer, boolean>
---@field show_busy_message fun(text: string)
---@field continue fun(callback: function): function wraps a callback of a step, so that the
---callback does nothing once the watchdog has stopped the switch or the restore

---A window of an application that the desktop manager leaves to macOS keeps its desktop in every
---state, and a window of a managed application keeps it while it is in sight.
---@param window table an hs.window
---@param context ExtraDesktopsContext
---@return boolean
local function does_known_window_keep_desktop(window, context)
    local application = window:application()
    if
        not app_pool.is_managed(context.read_app_pool(), track_windows.bundle_id_of(application))
    then
        return true
    end
    return not window:isMinimized() and not (application ~= nil and application:isHidden())
end

---The desktops that hold a window that keeps them from a removal.
---A window that Hammerspoon knows keeps its desktop as `does_known_window_keep_desktop` says.
---A window that the window server listed out of view at the last refresh of the inventory, and that
---Hammerspoon has not seen, keeps its desktop, because it is in sight there.
---A window that macOS lists on several desktops holds none of them.
---@param context ExtraDesktopsContext
---@return table<integer, boolean>
local function find_occupied_space_ids(context)
    local occupied = {}
    local known_by_id = track_windows.index_by_id(context.known_windows:list_all({}))
    for window_id, space_id in pairs(context.window_inventory.occupying_windows) do
        if not known_by_id[window_id] then
            occupied[space_id] = true
        end
    end
    for window_id, window in pairs(known_by_id) do
        local space_ids = read_desktops.list_window_space_ids(window_id)
        if #space_ids == 1 and does_known_window_keep_desktop(window, context) then
            occupied[space_ids[1]] = true
        end
    end
    return occupied
end

---The window among those that macOS lists on a desktop that keeps the desktop, at the check right
---before the removal of the desktop, as `does_known_window_keep_desktop` says.
---A window that macOS shows on every desktop keeps none of them.
---A window that Hammerspoon does not reach keeps its desktop when the inventory lists it on a
---desktop out of view, as in the plan of the removal, which leaves out the small windows.
---The inventory runs right before the removal, and it alone holds the windows of the applications
---without a Dock icon that the profiles do not name, which the window filter does not follow.
---The windows that the window filter leaves out come from one walk of every window of the
---applications that it follows, instead of one walk for each window as `hs.window.get` does.
---@param window_ids integer[]
---@param context ExtraDesktopsContext
---@return integer|nil
function extra_desktops.find_window_that_keeps_desktop(window_ids, context)
    local known_by_id = track_windows.index_by_id(context.known_windows:list_all({}))
    local all_by_id = nil
    for _, window_id in ipairs(window_ids) do
        if #read_desktops.list_window_space_ids(window_id) == 1 then
            local window = known_by_id[window_id]
            if not window then
                all_by_id = all_by_id
                    or track_windows.index_by_id(track_windows.list_followed_windows())
                window = all_by_id[window_id]
            end
            if window and does_known_window_keep_desktop(window, context) then
                return window_id
            end
            if not window and context.window_inventory.occupying_windows[window_id] then
                return window_id
            end
        end
    end
    return nil
end

---@param desktop ScreenDesktop
---@return integer|nil the space of the desktop, or of the last desktop of a screen with fewer
local function find_space_id_of(desktop)
    local screen = read_desktops.find_screen_desktops(desktop.screen_uuid)
    return screen and screen.space_ids[math.min(desktop.desktop_number, #screen.space_ids)]
end

---Shows each desktop through Mission Control, in one opening per desktop, because a press on a
---thumbnail closes Mission Control.
---@param desktops ScreenDesktop[]
---@param context ExtraDesktopsContext
---@param on_done fun(failures: string[])
function extra_desktops.show_desktops(desktops, context, on_done)
    local failures, index = {}, 0
    local function show_next()
        index = index + 1
        local desktop = desktops[index]
        if not desktop then
            on_done(failures)
            return
        end
        local space_id = find_space_id_of(desktop)
        if not space_id then
            table.insert(failures, string.format("%s has no desktops", desktop.slot_key))
            show_next()
            return
        end
        if not read_desktops.is_space_active(space_id) then
            context.show_busy_message(
                busy_message.describe_showing_desktop(desktop.desktop_number, desktop.slot_key)
            )
        end
        mission_control_desktops.show_space(
            space_id,
            context.timing,
            context.continue(function(error_message)
                if error_message then
                    table.insert(failures, error_message)
                end
                show_next()
            end)
        )
    end
    show_next()
end

---@param screen_uuid string
---@param count_by_slot table<string, integer>
---@param context ExtraDesktopsContext
---@return boolean whether the screen shows a desktop beyond the number of its slot
local function shows_extra_desktop(screen_uuid, count_by_slot, context)
    local screen = read_desktops.find_screen_desktops(screen_uuid)
    local slot =
        monitor_configuration.find_slot_of_screen(context.read_monitor_configuration(), screen_uuid)
    local count = slot and count_by_slot[slot.slot_key]
    if not screen or not count then
        return false
    end
    local shown_desktop_number = locate_desktops.find_shown_desktop_number(screen)
    return shown_desktop_number ~= nil and shown_desktop_number > count
end

---@param edits DesktopEdit[]
---@param removed_count integer
---@param desktop_of_focus ScreenDesktop|nil
---@return string|nil the message of the last opening of Mission Control, nil when it does nothing
local function describe_last_opening(edits, removed_count, desktop_of_focus)
    if #edits == 1 then
        return string.format(
            "Removing %d empty desktops from %s… please wait",
            removed_count,
            edits[1].slot_key
        )
    elseif #edits > 1 then
        return string.format("Removing %d empty desktops… please wait", removed_count)
    end
    if not desktop_of_focus then
        return nil
    end
    local space_id = find_space_id_of(desktop_of_focus)
    if space_id and not read_desktops.is_space_active(space_id) then
        return busy_message.describe_showing_desktop(
            desktop_of_focus.desktop_number,
            desktop_of_focus.slot_key
        )
    end
    return nil
end

---Removes the desktops beyond the number of each slot that do not show and hold no window that
---keeps them, from the end of each screen.
---The removals of every screen and the press on the desktop of the screen of the focus go in one
---opening of Mission Control, because the press closes it.
---A desktop beyond the number that shows on the screen of the focus would stay in view until that
---press, so the desktop of the focus then shows first, in an opening of its own.
---@param count_by_slot table<string, integer> the number of desktops of each slot
---@param desktop_of_focus ScreenDesktop|nil the recorded desktop of the screen of the focus
---@param context ExtraDesktopsContext
---@param on_done fun(failures: string[])
function extra_desktops.remove_extra_desktops(count_by_slot, desktop_of_focus, context, on_done)
    local timing = context.timing
    local function find_keeping_window(window_ids)
        return extra_desktops.find_window_that_keeps_desktop(window_ids, context)
    end
    local function remove_and_show(failures)
        window_inventory.refresh_from_now(
            context.window_inventory,
            context.list_filter_window_ids,
            context.continue(function()
                local removals = desktop_counts.plan_removals(
                    count_by_slot,
                    context.read_monitor_configuration(),
                    read_desktops.read_desktop_layout(),
                    find_occupied_space_ids(context)
                )
                local edits, removed_count = {}, 0
                for _, removal in ipairs(removals) do
                    if removal.staying_count > 0 then
                        context.log.f(
                            "%s keeps %d desktops beyond its %d, because they show or hold a"
                                .. " window, or lie below one that does, as the empty desktops %s",
                            removal.slot_key,
                            removal.staying_count,
                            removal.count,
                            table.concat(removal.empty_staying_space_ids, ", ")
                        )
                    end
                    if #removal.space_ids > 0 and read_screens.find_screen(removal.screen_uuid) then
                        context.log.f(
                            "removing the empty desktops %s beyond desktop %d of %s",
                            table.concat(removal.space_ids, ", "),
                            removal.count,
                            removal.slot_key
                        )
                        table.insert(edits, {
                            screen_uuid = removal.screen_uuid,
                            slot_key = removal.slot_key,
                            desktops_to_add = 0,
                            space_ids_to_remove = removal.space_ids,
                        })
                        removed_count = removed_count + #removal.space_ids
                    end
                end
                local message = describe_last_opening(edits, removed_count, desktop_of_focus)
                if message then
                    context.show_busy_message(message)
                end
                local finish = context.continue(function(edit_failures)
                    on_done(concatenate_lists.concatenate(failures, edit_failures))
                end)
                local space_id = desktop_of_focus and find_space_id_of(desktop_of_focus)
                if space_id then
                    mission_control_desktops.edit_and_show_space(
                        edits,
                        space_id,
                        find_keeping_window,
                        timing,
                        finish
                    )
                    return
                end
                mission_control_desktops.edit(edits, find_keeping_window, timing, finish)
            end)
        )
    end
    if
        desktop_of_focus
        and shows_extra_desktop(desktop_of_focus.screen_uuid, count_by_slot, context)
    then
        extra_desktops.show_desktops({ desktop_of_focus }, context, remove_and_show)
        return
    end
    remove_and_show({})
end

---Gives the focus to the front window of the screen of the slot, when the focus is on another
---screen, because the last press in Mission Control may have been on another screen.
---@param slot_key string|nil
---@param context ExtraDesktopsContext
local function focus_screen_of_slot(slot_key, context)
    local slot = slot_key
        and monitor_configuration.find_slot(context.read_monitor_configuration(), slot_key)
    local screen = slot and read_desktops.find_screen_desktops(slot.screen_uuid)
    if
        not screen
        or read_desktops.read_desktop_layout().focused_space_id == screen.active_space_id
    then
        return
    end
    for _, window in ipairs(hs.window.orderedWindows()) do
        local window_id = window:id()
        if
            window_id
            and window:isStandard()
            and read_desktops.find_window_space_id(window_id) == screen.active_space_id
        then
            window:focus()
            return
        end
    end
    context.log.f("%s shows no window to take the focus", slot_key)
end

---Shows the recorded desktop of each screen, removes the desktops beyond the numbers of the
---arrangement, and shows the desktop of the screen of the focus in the last opening of Mission
---Control, which then has the focus.
---@param arrangement Arrangement
---@param desktops ScreenDesktop[] the desktops to show, the desktop of the screen of the focus last
---@param context ExtraDesktopsContext
---@param on_done fun(failures: string[])
function extra_desktops.show_desktops_and_remove_extra_ones(arrangement, desktops, context, on_done)
    local desktop_of_focus = desktops[#desktops]
    local other_desktops = { table.unpack(desktops, 1, math.max(#desktops - 1, 0)) }
    extra_desktops.show_desktops(other_desktops, context, function(show_failures)
        extra_desktops.remove_extra_desktops(
            desktop_counts.count_by_slot(arrangement),
            desktop_of_focus,
            context,
            function(removal_failures)
                focus_screen_of_slot(arrangement.focused_slot_key, context)
                on_done(concatenate_lists.concatenate(show_failures, removal_failures))
            end
        )
    end)
end

return extra_desktops
