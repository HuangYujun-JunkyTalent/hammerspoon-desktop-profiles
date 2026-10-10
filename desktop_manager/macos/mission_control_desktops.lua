---Adds and removes desktops by pressing the buttons of Mission Control through accessibility.
---macOS 27 keeps the accessibility tree of Mission Control under the process WindowManager.
---Earlier versions keep it under the Dock.
---https://github.com/Hammerspoon/hammerspoon/issues/3897 reports the move.
---The identifiers `mc.display`, `mc.spaces.add` and `mc.spaces.list` and the action
---`AXRemoveDesktop` are those that `hs.spaces` of Hammerspoon 1.1.1 uses with the Dock.
local poll_until = require("desktop_manager.macos.poll_until")
local read_desktops = require("desktop_manager.macos.read_desktops")
local retained_timers = require("desktop_manager.macos.retained_timers")

local mission_control_desktops = {}

local MISSION_CONTROL_OWNER_BUNDLE_IDS = { "com.apple.WindowManager", "com.apple.dock" }
local DISPLAY_SEARCH_DEPTH = 6
local BUTTON_SEARCH_DEPTH = 4
local MISSION_CONTROL_POLL_SECONDS = 0.1

---@param element table an hs.axuielement
---@param attribute string
---@return any
local function read_attribute(element, attribute)
    local is_successful, value = pcall(element.attributeValue, element, attribute)
    return is_successful and value or nil
end

---Depth-first search of the accessibility tree below `element`.
---@param element table an hs.axuielement
---@param is_wanted fun(element: table): boolean
---@param depth_left integer
---@return table|nil
local function find_descendant(element, is_wanted, depth_left)
    if depth_left <= 0 then
        return nil
    end
    for _, child in ipairs(read_attribute(element, "AXChildren") or {}) do
        if is_wanted(child) then
            return child
        end
        local found = find_descendant(child, is_wanted, depth_left - 1)
        if found then
            return found
        end
    end
    return nil
end

---@param identifier string
---@return fun(element: table): boolean
local function has_identifier(identifier)
    return function(element)
        return read_attribute(element, "AXIdentifier") == identifier
    end
end

---@param screen_id integer the `hs.screen:id()` of the display
---@return table|nil display_group the `mc.display` element, present while Mission Control shows
local function find_display_group(screen_id)
    for _, bundle_id in ipairs(MISSION_CONTROL_OWNER_BUNDLE_IDS) do
        local application = hs.application.applicationsForBundleID(bundle_id)[1]
        if application then
            local display_group = find_descendant(
                hs.axuielement.applicationElement(application),
                function(element)
                    return read_attribute(element, "AXIdentifier") == "mc.display"
                        and read_attribute(element, "AXDisplayID") == screen_id
                end,
                DISPLAY_SEARCH_DEPTH
            )
            if display_group then
                return display_group
            end
        end
    end
    return nil
end

---@param element table an hs.axuielement
---@param action string
---@return string|nil error_message
local function perform(element, action)
    local is_successful, result, error_message = pcall(element.performAction, element, action)
    if not is_successful then
        return tostring(result)
    end
    if not result then
        return string.format("Mission Control rejected %s: %s", action, tostring(error_message))
    end
    return nil
end

---Opens Mission Control, runs `action` with the group of the display, and closes Mission Control.
---@param screen_id integer
---@param timing Timing
---@param action fun(display_group: table, finish: fun(error_message: string|nil))
---@param on_done fun(error_message: string|nil)
local function with_mission_control(screen_id, timing, action, on_done)
    local was_open = find_display_group(screen_id) ~= nil
    if not was_open then
        hs.spaces.toggleMissionControl()
    end
    local function finish(error_message)
        if not was_open then
            hs.spaces.toggleMissionControl()
        end
        retained_timers.after(timing.mission_control_press_gap_seconds, function()
            on_done(error_message)
        end)
    end
    local display_group = nil
    poll_until.wait(
        function()
            display_group = find_display_group(screen_id)
            return display_group ~= nil
        end,
        timing.mission_control_timeout_seconds,
        MISSION_CONTROL_POLL_SECONDS,
        function(is_found)
            if not is_found then
                finish(string.format("Mission Control showed no group for display %d", screen_id))
                return
            end
            retained_timers.after(timing.mission_control_press_gap_seconds, function()
                action(display_group, finish)
            end)
        end
    )
end

---@param screen_id integer
---@param count integer
---@param timing Timing
---@param on_done fun(error_message: string|nil)
function mission_control_desktops.add_desktops(screen_id, count, timing, on_done)
    with_mission_control(screen_id, timing, function(display_group, finish)
        local add_button =
            find_descendant(display_group, has_identifier("mc.spaces.add"), BUTTON_SEARCH_DEPTH)
        if not add_button then
            finish("Mission Control showed no button to add a desktop")
            return
        end
        local remaining = count
        local function press_next()
            if remaining == 0 then
                finish(nil)
                return
            end
            remaining = remaining - 1
            local error_message = perform(add_button, "AXPress")
            if error_message then
                finish(error_message)
                return
            end
            retained_timers.after(timing.mission_control_press_gap_seconds, press_next)
        end
        press_next()
    end, on_done)
end

---@param screen_id integer
---@param screen_uuid string
---@param space_ids integer[]
---@param timing Timing
---@param on_done fun(error_message: string|nil)
function mission_control_desktops.remove_desktops(
    screen_id,
    screen_uuid,
    space_ids,
    timing,
    on_done
)
    with_mission_control(screen_id, timing, function(display_group, finish)
        local spaces_list =
            find_descendant(display_group, has_identifier("mc.spaces.list"), BUTTON_SEARCH_DEPTH)
        if not spaces_list then
            finish("Mission Control showed no list of desktops")
            return
        end
        local positions = {}
        for position, space_id in ipairs(read_desktops.list_all_space_ids_of_screen(screen_uuid)) do
            for _, removed_space_id in ipairs(space_ids) do
                if space_id == removed_space_id then
                    table.insert(positions, position)
                end
            end
        end
        table.sort(positions, function(first, second)
            return first > second
        end)
        local next_index = 1
        local function remove_next()
            local position = positions[next_index]
            if position == nil then
                finish(nil)
                return
            end
            next_index = next_index + 1
            local thumbnail = (read_attribute(spaces_list, "AXChildren") or {})[position]
            if not thumbnail then
                finish(string.format("Mission Control listed no desktop at position %d", position))
                return
            end
            local error_message = perform(thumbnail, "AXRemoveDesktop")
            if error_message then
                finish(error_message)
                return
            end
            retained_timers.after(timing.mission_control_press_gap_seconds, remove_next)
        end
        remove_next()
    end, on_done)
end

return mission_control_desktops
