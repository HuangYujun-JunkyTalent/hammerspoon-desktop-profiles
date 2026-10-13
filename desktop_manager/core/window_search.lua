local fuzzy_match = require("desktop_manager.core.fuzzy_match")

---The search of the windows: every window, the applications in a row, the typed text, the
---application that the mouse hovers over or chose, the windows in view and the selected one.
---The windows in view are the windows of the chosen application, else of the hovered application,
---else the windows that match the typed words at any level, and every window while no word is
---typed.
local window_search = {
    ---The directions of the arrow keys in the grid of the previews.
    LEFT = "left",
    RIGHT = "right",
    UP = "up",
    DOWN = "down",
}

---A window of the search, from accessibility or from the window server.
---@class SearchEntry
---@field window_id integer
---@field title string
---@field bundle_id string
---@field app_name string

---@class SearchApplication
---@field bundle_id string
---@field app_name string
---@field number integer|nil the number that the numbering profile gives the application
---@field window_ids integer[]

---@class WindowSearch
---@field entries SearchEntry[] every window, the most recently focused first
---@field number_by_bundle_id table<string, integer>
---@field applications SearchApplication[] in the order of their most recent windows
---@field initial_window_id integer|nil the window selected while every window shows
---@field text string the typed text
---@field hovered_bundle_id string|nil the application that the mouse hovers over
---@field chosen_bundle_id string|nil the application that a click chose
---@field shown integer[] the windows in view, in their order
---@field levels table<integer, string> the level of `fuzzy_match` of each window that matches the
---typed words
---@field selected_window_id integer|nil a window in view, or nil when no window is in view

---What the panel shows.
---@class SearchView
---@field line SearchLine
---@field windows SearchViewWindow[]
---@field applications SearchViewApplication[]

---@class SearchLine
---@field text string the typed text
---@field placeholder string the text that shows while nothing is typed
---@field summary string which windows the panel shows

---@class SearchViewWindow
---@field window_id integer
---@field title string
---@field app_name string
---@field bundle_id string
---@field match_level string|nil
---@field is_selected boolean

---@class SearchViewApplication
---@field bundle_id string
---@field app_name string
---@field number integer|nil
---@field match_level string|nil the best level of the windows of the application
---@field is_faded boolean whether no window of the application matches the typed words
---@field is_hovered boolean
---@field is_chosen boolean

local PLACEHOLDER = "Type to search the titles and the applications"

---@param entries SearchEntry[]
---@param number_by_bundle_id table<string, integer>
---@return SearchApplication[]
local function group_applications(entries, number_by_bundle_id)
    local applications, by_bundle_id = {}, {}
    for _, entry in ipairs(entries) do
        local application = by_bundle_id[entry.bundle_id]
        if not application then
            application = {
                bundle_id = entry.bundle_id,
                app_name = entry.app_name,
                number = number_by_bundle_id[entry.bundle_id],
                window_ids = {},
            }
            by_bundle_id[entry.bundle_id] = application
            table.insert(applications, application)
        end
        table.insert(application.window_ids, entry.window_id)
    end
    return applications
end

---@param search WindowSearch
---@return boolean
local function has_words(search)
    return #fuzzy_match.split_words(search.text) > 0
end

---@param search WindowSearch
---@return table<integer, string> levels
---@return integer[] matches from the best score down, in the order of the entries at equal scores
local function rank_matches(search)
    local matches = {}
    if not has_words(search) then
        return {}, {}
    end
    for position, entry in ipairs(search.entries) do
        local score = fuzzy_match.score(search.text, { entry.app_name, entry.title })
        if score then
            table.insert(
                matches,
                { window_id = entry.window_id, score = score, position = position }
            )
        end
    end
    table.sort(matches, function(first, second)
        if first.score ~= second.score then
            return first.score > second.score
        end
        return first.position < second.position
    end)
    local levels, order = {}, {}
    for _, match in ipairs(matches) do
        levels[match.window_id] = fuzzy_match.level_of(match.score)
        table.insert(order, match.window_id)
    end
    return levels, order
end

---@param search WindowSearch
---@param bundle_id string|nil
---@return SearchApplication|nil
local function find_application(search, bundle_id)
    for _, application in ipairs(search.applications) do
        if application.bundle_id == bundle_id then
            return application
        end
    end
    return nil
end

---@param window_ids integer[]
---@param window_id integer|nil
---@return integer the position of the window, or 0 when the list does not hold it
local function find_position(window_ids, window_id)
    for index, listed_id in ipairs(window_ids) do
        if listed_id == window_id then
            return index
        end
    end
    return 0
end

---@param search WindowSearch
---@return WindowSearch a copy whose fields the caller changes
local function copy(search)
    local copied = {}
    for key, value in pairs(search) do
        copied[key] = value
    end
    return copied
end

---Works out the matches, the windows in view and the selection of a search whose text,
---applications or entries changed.
---The preferred window stays selected while it is in view.
---Otherwise the initial window is selected while every window shows, and the first window in view
---when some show.
---@param search WindowSearch
---@param preferred_window_id integer|nil
---@return WindowSearch the same table, completed
local function complete(search, preferred_window_id)
    local levels, matches = rank_matches(search)
    search.levels = levels
    local focused = find_application(search, search.chosen_bundle_id or search.hovered_bundle_id)
    local is_every_window_shown = not focused and not has_words(search)
    if focused then
        search.shown = focused.window_ids
    elseif has_words(search) then
        search.shown = matches
    else
        search.shown = {}
        for _, entry in ipairs(search.entries) do
            table.insert(search.shown, entry.window_id)
        end
    end
    if find_position(search.shown, preferred_window_id) > 0 then
        search.selected_window_id = preferred_window_id
    elseif is_every_window_shown and find_position(search.shown, search.initial_window_id) > 0 then
        search.selected_window_id = search.initial_window_id
    else
        search.selected_window_id = search.shown[1]
    end
    return search
end

---@param entries SearchEntry[] the most recently focused first
---@param number_by_bundle_id table<string, integer>
---@param initial_window_id integer|nil
---@return WindowSearch
function window_search.start(entries, number_by_bundle_id, initial_window_id)
    return complete({
        entries = entries,
        number_by_bundle_id = number_by_bundle_id,
        applications = group_applications(entries, number_by_bundle_id),
        initial_window_id = initial_window_id,
        text = "",
    }, nil)
end

---Takes a new list of the windows, as when the window server reports windows that accessibility
---does not reach, and keeps the text, the applications of the mouse and the selection.
---@param search WindowSearch
---@param entries SearchEntry[]
---@return WindowSearch
function window_search.with_entries(search, entries)
    local updated = copy(search)
    updated.entries = entries
    updated.applications = group_applications(entries, search.number_by_bundle_id)
    return complete(updated, search.selected_window_id)
end

---Typing drops the applications of the mouse, so the matches show with the best one selected.
---@param search WindowSearch
---@param text string
---@return WindowSearch
function window_search.with_text(search, text)
    local updated = copy(search)
    updated.text = text
    updated.hovered_bundle_id = nil
    updated.chosen_bundle_id = nil
    return complete(updated, nil)
end

---@param search WindowSearch
---@param characters string
---@return WindowSearch
function window_search.type_text(search, characters)
    return window_search.with_text(search, search.text .. characters)
end

---@param search WindowSearch
---@return WindowSearch
function window_search.delete_last_character(search)
    local is_valid, start = pcall(utf8.offset, search.text, -1)
    if not is_valid or not start then
        return window_search.with_text(search, search.text:sub(1, -2))
    end
    return window_search.with_text(search, search.text:sub(1, start - 1))
end

---@param search WindowSearch
---@return WindowSearch
function window_search.clear_text(search)
    return window_search.with_text(search, "")
end

---Shows the windows of the application while no application is chosen, or the matches again for
---nil, as when the mouse leaves the panel.
---@param search WindowSearch
---@param bundle_id string|nil
---@return WindowSearch
function window_search.hover_application(search, bundle_id)
    if bundle_id == search.hovered_bundle_id then
        return search
    end
    local updated = copy(search)
    updated.hovered_bundle_id = bundle_id
    return complete(updated, search.selected_window_id)
end

---Chooses the application, so its windows stay in view, or releases it when it is chosen already.
---@param search WindowSearch
---@param bundle_id string
---@return WindowSearch
function window_search.choose_application(search, bundle_id)
    local updated = copy(search)
    updated.chosen_bundle_id = search.chosen_bundle_id ~= bundle_id and bundle_id or nil
    return complete(updated, search.selected_window_id)
end

---Selects a window in view, as the mouse does when it hovers over the window.
---@param search WindowSearch
---@param window_id integer
---@return WindowSearch
function window_search.select_window(search, window_id)
    if window_id == search.selected_window_id or find_position(search.shown, window_id) == 0 then
        return search
    end
    local updated = copy(search)
    updated.selected_window_id = window_id
    return updated
end

---@param search WindowSearch
---@param step integer 1 for the next window and -1 for the previous one
---@return WindowSearch
local function move_selection(search, step)
    if #search.shown == 0 then
        return search
    end
    local position = find_position(search.shown, search.selected_window_id)
    return window_search.select_window(
        search,
        search.shown[(position - 1 + step) % #search.shown + 1]
    )
end

---Selects the next window in view, and the first after the last, as Tab does.
---@param search WindowSearch
---@return WindowSearch
function window_search.select_next(search)
    return move_selection(search, 1)
end

---@param search WindowSearch
---@return WindowSearch
function window_search.select_previous(search)
    return move_selection(search, -1)
end

---The position that a move from a position reaches in a grid filled row by row from the left, or
---the same position at the edge of the grid.
---A move down onto a shorter last row reaches its last position.
local GRID_MOVES = {
    [window_search.LEFT] = function(position, column_count)
        return (position - 1) % column_count > 0 and position - 1 or position
    end,
    [window_search.RIGHT] = function(position, column_count, count)
        return (position % column_count > 0 and position < count) and position + 1 or position
    end,
    [window_search.UP] = function(position, column_count)
        return position > column_count and position - column_count or position
    end,
    [window_search.DOWN] = function(position, column_count, count)
        local row = (position - 1) // column_count
        local last_row = (count - 1) // column_count
        return row < last_row and math.min(position + column_count, count) or position
    end,
}

---Selects the window beside, above or below the selected one in the grid of the windows in view,
---as the arrow keys do.
---@param search WindowSearch
---@param column_count integer the columns of the grid in the panel
---@param direction string a direction of `window_search`
---@return WindowSearch
function window_search.move_in_grid(search, column_count, direction)
    local move = GRID_MOVES[direction]
    if not move then
        error(string.format("the direction %q names no direction", tostring(direction)), 2)
    end
    local position = find_position(search.shown, search.selected_window_id)
    if position == 0 then
        return search.shown[1] and window_search.select_window(search, search.shown[1]) or search
    end
    local target = move(position, math.max(1, column_count), #search.shown)
    return window_search.select_window(search, search.shown[target])
end

---@param search WindowSearch
---@return integer|nil
function window_search.find_selected_window_id(search)
    return search.selected_window_id
end

---@param count integer
---@return string
local function count_windows(count)
    return string.format("%d %s", count, count == 1 and "window" or "windows")
end

---@param search WindowSearch
---@return SearchLine
function window_search.describe_search_line(search)
    local focused = find_application(search, search.chosen_bundle_id or search.hovered_bundle_id)
    local summary
    if focused then
        summary = string.format(
            "%s of %s%s",
            count_windows(#focused.window_ids),
            focused.app_name,
            search.chosen_bundle_id and ", chosen" or ""
        )
    elseif #search.entries == 0 then
        summary = "no window is open"
    elseif has_words(search) and #search.shown == 0 then
        summary = "no window matches"
    elseif has_words(search) then
        summary = string.format("%d of %s match", #search.shown, count_windows(#search.entries))
    else
        summary = count_windows(#search.entries)
    end
    return { text = search.text, placeholder = PLACEHOLDER, summary = summary }
end

local LEVEL_RANKS = { [fuzzy_match.STRONG] = 3, [fuzzy_match.MEDIUM] = 2, [fuzzy_match.WEAK] = 1 }

---@param search WindowSearch
---@param application SearchApplication
---@return string|nil the best level among the windows of the application
local function find_best_level(search, application)
    local best = nil
    for _, window_id in ipairs(application.window_ids) do
        local level = search.levels[window_id]
        if level and (not best or LEVEL_RANKS[level] > LEVEL_RANKS[best]) then
            best = level
        end
    end
    return best
end

---@param search WindowSearch
---@return SearchView
function window_search.describe_view(search)
    local entry_by_id = {}
    for _, entry in ipairs(search.entries) do
        entry_by_id[entry.window_id] = entry
    end
    local windows = {}
    for _, window_id in ipairs(search.shown) do
        local entry = entry_by_id[window_id]
        table.insert(windows, {
            window_id = window_id,
            title = entry.title,
            app_name = entry.app_name,
            bundle_id = entry.bundle_id,
            match_level = search.levels[window_id],
            is_selected = window_id == search.selected_window_id,
        })
    end
    local applications = {}
    for _, application in ipairs(search.applications) do
        local level = find_best_level(search, application)
        table.insert(applications, {
            bundle_id = application.bundle_id,
            app_name = application.app_name,
            number = application.number,
            match_level = level,
            is_faded = has_words(search) and level == nil,
            is_hovered = application.bundle_id == search.hovered_bundle_id,
            is_chosen = application.bundle_id == search.chosen_bundle_id,
        })
    end
    return {
        line = window_search.describe_search_line(search),
        windows = windows,
        applications = applications,
    }
end

return window_search
