local deep_copy = require("desktop_manager.core.deep_copy")

local app_numbers = {}

---The number of an application in a profile, which a shortcut such as Control-Option-3 reaches.
---@class AppNumber
---@field number integer
---@field bundle_id string
---@field app_name string
---@field is_chosen_by_user boolean

---@class RecordedApplication
---@field bundle_id string
---@field app_name string
---@field slot_index integer
---@field desktop_number integer
---@field left_edge number

---@param entries AppNumber[]
---@param number integer
---@return AppNumber|nil
function app_numbers.find_by_number(entries, number)
    for _, entry in ipairs(entries) do
        if entry.number == number then
            return deep_copy.copy(entry)
        end
    end
    return nil
end

---@param first RecordedApplication
---@param second RecordedApplication
---@return boolean whether the first comes before the second
local function comes_before(first, second)
    if first.slot_index ~= second.slot_index then
        return first.slot_index < second.slot_index
    end
    if first.desktop_number ~= second.desktop_number then
        return first.desktop_number < second.desktop_number
    end
    if first.left_edge ~= second.left_edge then
        return first.left_edge < second.left_edge
    end
    return first.app_name < second.app_name
end

---The applications that the arrangement records in sight, each at the place of its first window by
---screen, desktop and left edge, in that order.
---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@return RecordedApplication[]
local function order_recorded_applications(arrangement, configuration)
    local slot_index_by_key = {}
    for index, slot in ipairs(configuration.slots) do
        slot_index_by_key[slot.slot_key] = index
    end
    local by_bundle = {}
    for _, record in ipairs(arrangement.windows) do
        local slot_index = record.slot_key and slot_index_by_key[record.slot_key]
        if not record.is_out_of_sight and slot_index and record.desktop_number then
            local candidate = {
                bundle_id = record.bundle_id,
                app_name = record.app_name,
                slot_index = slot_index,
                desktop_number = record.desktop_number,
                left_edge = record.unit_frame and record.unit_frame.x or 0,
            }
            local current = by_bundle[record.bundle_id]
            if not current or comes_before(candidate, current) then
                by_bundle[record.bundle_id] = candidate
            end
        end
    end
    local applications = {}
    for _, application in pairs(by_bundle) do
        table.insert(applications, application)
    end
    table.sort(applications, comes_before)
    return applications
end

---@param entries AppNumber[]
---@return AppNumber[]
local function sort_by_number(entries)
    local sorted = deep_copy.copy(entries)
    table.sort(sorted, function(first, second)
        return first.number < second.number
    end)
    return sorted
end

---Keeps the numbers that the user chose, keeps a default number while the profile records a window
---of its application, in sight or out of sight, and gives the lowest free numbers to the other
---applications in sight.
---The other applications take numbers in the order of the screens, the desktops and the left edges
---of their windows.
---@param entries AppNumber[]
---@param arrangement Arrangement
---@param configuration MonitorConfiguration
---@param number_count integer the highest number that a shortcut reaches
---@return AppNumber[]
function app_numbers.update_defaults(entries, arrangement, configuration, number_count)
    local applications = order_recorded_applications(arrangement, configuration)
    local is_recorded = {}
    for _, record in ipairs(arrangement.windows) do
        is_recorded[record.bundle_id] = true
    end
    local kept, used_numbers, numbered_bundles = {}, {}, {}
    for _, entry in ipairs(entries) do
        if entry.is_chosen_by_user or is_recorded[entry.bundle_id] then
            table.insert(kept, deep_copy.copy(entry))
            used_numbers[entry.number] = true
            numbered_bundles[entry.bundle_id] = true
        end
    end
    local next_number = 1
    for _, application in ipairs(applications) do
        if not numbered_bundles[application.bundle_id] then
            while used_numbers[next_number] do
                next_number = next_number + 1
            end
            if next_number > number_count then
                break
            end
            table.insert(kept, {
                number = next_number,
                bundle_id = application.bundle_id,
                app_name = application.app_name,
                is_chosen_by_user = false,
            })
            used_numbers[next_number] = true
            numbered_bundles[application.bundle_id] = true
        end
    end
    return sort_by_number(kept)
end

---Gives the number to the application, and takes it from the application that held it.
---The application gives up any other number it held.
---@param entries AppNumber[]
---@param number integer
---@param bundle_id string
---@param app_name string
---@return AppNumber[]
function app_numbers.choose(entries, number, bundle_id, app_name)
    local chosen = {}
    for _, entry in ipairs(entries) do
        if entry.number ~= number and entry.bundle_id ~= bundle_id then
            table.insert(chosen, deep_copy.copy(entry))
        end
    end
    table.insert(chosen, {
        number = number,
        bundle_id = bundle_id,
        app_name = app_name,
        is_chosen_by_user = true,
    })
    return sort_by_number(chosen)
end

---Frees the number, so that the next update of the defaults gives it again.
---@param entries AppNumber[]
---@param number integer
---@return AppNumber[]
function app_numbers.release(entries, number)
    local kept = {}
    for _, entry in ipairs(entries) do
        if entry.number ~= number then
            table.insert(kept, deep_copy.copy(entry))
        end
    end
    return kept
end

---The window after the focused one in the order of the ids, or the first when none is focused.
---@param window_ids integer[]
---@param focused_window_id integer|nil
---@return integer|nil
function app_numbers.find_next_window_id(window_ids, focused_window_id)
    local sorted = { table.unpack(window_ids) }
    table.sort(sorted)
    for index, window_id in ipairs(sorted) do
        if window_id == focused_window_id then
            return sorted[index % #sorted + 1]
        end
    end
    return sorted[1]
end

---The index of the window that the first press of the list selects among the sorted window ids of
---an application, 0 when it selects none of them.
---The first press selects the window after the focused one when the application is in front, and
---otherwise the window of the application that had the focus last.
---@param sorted_window_ids integer[]
---@param last_focused_window_id integer|nil the window of the application that had the focus last
---@param focused_window_id integer|nil the focused window when it belongs to the application and
---the application is in front, and nil otherwise
---@return integer
function app_numbers.find_first_selection_index(
    sorted_window_ids,
    last_focused_window_id,
    focused_window_id
)
    local first_window_id = last_focused_window_id
    if focused_window_id then
        first_window_id = app_numbers.find_next_window_id(sorted_window_ids, focused_window_id)
    end
    local first_window_index = 0
    for index, window_id in ipairs(sorted_window_ids) do
        if window_id == first_window_id then
            first_window_index = index
        end
    end
    return first_window_index
end

return app_numbers
