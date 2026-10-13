---The applications whose windows the desktop manager manages, one choice for every profile.
---The desktop manager never minimizes, moves, opens or records a window of an application outside
---the pool, and macOS keeps managing those windows.
---Each mode keeps its own list, so that changing the mode leaves the ticks of the other mode.
local app_pool = {
    ---Every application except the listed ones, the default, which manages every application while
    ---its list is empty.
    SKIP_LISTED = "skip_listed",
    ---The listed applications alone.
    MANAGE_LISTED = "manage_listed",
}

local ORDER = { app_pool.SKIP_LISTED, app_pool.MANAGE_LISTED }

local LABELS = {
    [app_pool.SKIP_LISTED] = "Manage every application except the ticked ones",
    [app_pool.MANAGE_LISTED] = "Manage only the ticked applications",
}

---@class ListedApplication
---@field bundle_id string
---@field app_name string

---@class AppPool
---@field mode string a mode of `app_pool`
---@field skip_listed ListedApplication[]
---@field manage_listed ListedApplication[]

---An application that the window of the pool offers, with whether the list of the mode names it.
---@class AppPoolChoice
---@field bundle_id string
---@field app_name string
---@field is_listed boolean

---@return AppPool
function app_pool.new()
    return { mode = app_pool.SKIP_LISTED, skip_listed = {}, manage_listed = {} }
end

---@param mode any
---@return boolean
function app_pool.is_valid_mode(mode)
    return LABELS[mode] ~= nil
end

---@return string[]
function app_pool.all_modes()
    return { table.unpack(ORDER) }
end

---@param mode string
---@return string
function app_pool.label_of(mode)
    local label = LABELS[mode]
    if not label then
        error(string.format("unknown mode of the application pool %q", tostring(mode)), 2)
    end
    return label
end

---@param list ListedApplication[]
---@param bundle_id string
---@return boolean
local function names(list, bundle_id)
    for _, application in ipairs(list) do
        if application.bundle_id == bundle_id then
            return true
        end
    end
    return false
end

---@param list ListedApplication[]
---@return ListedApplication[]
local function copy_list(list)
    local copied = {}
    for _, application in ipairs(list) do
        table.insert(copied, { bundle_id = application.bundle_id, app_name = application.app_name })
    end
    return copied
end

---@param pool AppPool
---@return AppPool
local function copy_pool(pool)
    return {
        mode = pool.mode,
        skip_listed = copy_list(pool.skip_listed),
        manage_listed = copy_list(pool.manage_listed),
    }
end

---@param pool AppPool
---@return boolean whether the pool holds every application, so that nothing needs filtering
function app_pool.holds_every_application(pool)
    return pool.mode == app_pool.SKIP_LISTED and #pool.skip_listed == 0
end

---@param pool AppPool
---@param bundle_id string
---@return boolean
function app_pool.is_managed(pool, bundle_id)
    local is_listed = names(pool[pool.mode], bundle_id)
    if pool.mode == app_pool.MANAGE_LISTED then
        return is_listed
    end
    return not is_listed
end

---@param pool AppPool
---@param mode string
---@return AppPool
function app_pool.with_mode(pool, mode)
    if not app_pool.is_valid_mode(mode) then
        error(string.format("unknown mode of the application pool %q", tostring(mode)), 2)
    end
    local updated = copy_pool(pool)
    updated.mode = mode
    return updated
end

---Ticks or unticks the application in the list of the current mode.
---@param pool AppPool
---@param bundle_id string
---@param app_name string
---@param is_listed boolean
---@return AppPool
function app_pool.with_listed(pool, bundle_id, app_name, is_listed)
    local updated = copy_pool(pool)
    local list = {}
    for _, application in ipairs(updated[updated.mode]) do
        if application.bundle_id ~= bundle_id then
            table.insert(list, application)
        end
    end
    if is_listed then
        table.insert(list, { bundle_id = bundle_id, app_name = app_name })
    end
    updated[updated.mode] = list
    return updated
end

---@generic T : { bundle_id: string }
---@param pool AppPool
---@param items T[] records or windows, each with a bundle id
---@return T[] the items of managed applications, in their order
function app_pool.keep_managed(pool, items)
    if app_pool.holds_every_application(pool) then
        return items
    end
    local kept = {}
    for _, item in ipairs(items) do
        if app_pool.is_managed(pool, item.bundle_id) then
            table.insert(kept, item)
        end
    end
    return kept
end

---The applications that the window offers: the ones in the list of the current mode and the
---running ones with a window, each once and ordered by name.
---@param pool AppPool
---@param running ListedApplication[]
---@return AppPoolChoice[]
function app_pool.list_choices(pool, running)
    local choices, seen = {}, {}
    local function add(application)
        if not seen[application.bundle_id] then
            seen[application.bundle_id] = true
            table.insert(choices, {
                bundle_id = application.bundle_id,
                app_name = application.app_name,
                is_listed = names(pool[pool.mode], application.bundle_id),
            })
        end
    end
    for _, application in ipairs(pool[pool.mode]) do
        add(application)
    end
    for _, application in ipairs(running) do
        add(application)
    end
    table.sort(choices, function(first, second)
        if first.app_name:lower() ~= second.app_name:lower() then
            return first.app_name:lower() < second.app_name:lower()
        end
        return first.bundle_id < second.bundle_id
    end)
    return choices
end

---@param pool AppPool
---@return string one line on the pool, for the diagnostics
function app_pool.describe(pool)
    local names_of_list = {}
    for _, application in ipairs(pool[pool.mode]) do
        table.insert(names_of_list, application.app_name)
    end
    local listed = #names_of_list > 0 and table.concat(names_of_list, ", ") or "none"
    if pool.mode == app_pool.MANAGE_LISTED then
        return "only " .. listed
    end
    return "every application except " .. listed
end

---@param raw any
---@return ListedApplication[]
local function decode_list(raw)
    local list = {}
    for _, raw_application in ipairs(type(raw) == "table" and raw or {}) do
        if type(raw_application) == "table" and type(raw_application.bundle_id) == "string" then
            table.insert(list, {
                bundle_id = raw_application.bundle_id,
                app_name = tostring(raw_application.app_name or raw_application.bundle_id),
            })
        end
    end
    return list
end

---Reads a pool decoded from JSON.
---A state of 2026-10-12 holds `managed_applications` instead, the list of the managed applications
---alone, which becomes the list of `MANAGE_LISTED`.
---@param raw any the `app_pool` of the state
---@param raw_managed_applications any the `managed_applications` of an older state
---@return AppPool
function app_pool.decode(raw, raw_managed_applications)
    local pool = app_pool.new()
    if type(raw) == "table" then
        pool.mode = app_pool.is_valid_mode(raw.mode) and raw.mode or app_pool.SKIP_LISTED
        pool.skip_listed = decode_list(raw.skip_listed)
        pool.manage_listed = decode_list(raw.manage_listed)
        return pool
    end
    local managed = decode_list(raw_managed_applications)
    if #managed > 0 then
        pool.mode = app_pool.MANAGE_LISTED
        pool.manage_listed = managed
    end
    return pool
end

return app_pool
