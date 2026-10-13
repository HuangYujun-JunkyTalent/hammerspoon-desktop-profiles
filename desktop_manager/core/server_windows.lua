---The windows that the window server of macOS lists and accessibility does not reach: the windows
---of applications with a Dock icon on the desktops out of view.
---Accessibility reaches the windows of the desktops in view, the minimized windows and the windows
---of hidden applications, so a window of the window server on a desktop in view is a panel or an
---overlay that the window filter leaves out on purpose.
local server_windows = {}

---A window smaller than this is no window that a user works in, such as the windows of one point
---that Calendar keeps.
local MIN_WIDTH = 100
local MIN_HEIGHT = 50

---A window as `list_server_windows.js` prints it.
---@class ServerWindowRow
---@field window_id integer
---@field pid integer the process id of the owner
---@field title string empty without the permission for Screen Recording
---@field x number the left edge, in the coordinates of hs.screen, whose origin is the top left
---corner of the main screen
---@field y number the top edge
---@field w number
---@field h number

---A window that accessibility does not reach, with its application and its desktop.
---@class ServerWindow
---@field window_id integer
---@field bundle_id string
---@field app_name string
---@field title string
---@field space_id integer
---@field frame Rect

---@class ServerApplication
---@field bundle_id string
---@field app_name string

---@param rows ServerWindowRow[]
---@param hidden_space_by_window_id table<integer, integer> the desktop of each window on a desktop
---out of view
---@return integer[] the process ids of the owners of those windows, each once
function server_windows.list_owner_pids(rows, hidden_space_by_window_id)
    local pids, is_listed = {}, {}
    for _, row in ipairs(rows) do
        if hidden_space_by_window_id[row.window_id] and not is_listed[row.pid] then
            is_listed[row.pid] = true
            table.insert(pids, row.pid)
        end
    end
    return pids
end

---@param rows ServerWindowRow[]
---@param hidden_space_by_window_id table<integer, integer>
---@param application_by_pid table<integer, ServerApplication> the applications with a Dock icon
---@param known_window_ids table<integer, boolean> the windows that accessibility reaches
---@return ServerWindow[] in the order of the rows
function server_windows.select_unreached_windows(
    rows,
    hidden_space_by_window_id,
    application_by_pid,
    known_window_ids
)
    local windows = {}
    for _, row in ipairs(rows) do
        local space_id = hidden_space_by_window_id[row.window_id]
        local application = application_by_pid[row.pid]
        if
            space_id
            and application
            and not known_window_ids[row.window_id]
            and row.w >= MIN_WIDTH
            and row.h >= MIN_HEIGHT
        then
            table.insert(windows, {
                window_id = row.window_id,
                bundle_id = application.bundle_id,
                app_name = application.app_name,
                title = type(row.title) == "string" and row.title or "",
                space_id = space_id,
                frame = { x = row.x, y = row.y, w = row.w, h = row.h },
            })
        end
    end
    return windows
end

---The desktops out of view that hold a window of an application with a Dock icon.
---A window that macOS lists on several desktops, such as the window of an application assigned to
---all desktops, holds none of them.
---@param rows ServerWindowRow[]
---@param hidden_space_ids_by_window_id table<integer, integer[]> the desktops out of view that
---macOS lists for each window
---@param application_by_pid table<integer, ServerApplication> the applications with a Dock icon
---@return table<integer, boolean>
function server_windows.find_occupied_space_ids(
    rows,
    hidden_space_ids_by_window_id,
    application_by_pid
)
    local occupied = {}
    for _, row in ipairs(rows) do
        local space_ids = hidden_space_ids_by_window_id[row.window_id]
        if
            space_ids
            and #space_ids == 1
            and application_by_pid[row.pid]
            and row.w >= MIN_WIDTH
            and row.h >= MIN_HEIGHT
        then
            occupied[space_ids[1]] = true
        end
    end
    return occupied
end

---The windows of an earlier list that are still on a desktop out of view and still out of reach,
---each with the desktop where it is now.
---@param windows ServerWindow[]
---@param hidden_space_by_window_id table<integer, integer>
---@param known_window_ids table<integer, boolean>
---@return ServerWindow[]
function server_windows.keep_unreached_windows(windows, hidden_space_by_window_id, known_window_ids)
    local kept = {}
    for _, window in ipairs(windows) do
        local space_id = hidden_space_by_window_id[window.window_id]
        if space_id and not known_window_ids[window.window_id] then
            table.insert(kept, {
                window_id = window.window_id,
                bundle_id = window.bundle_id,
                app_name = window.app_name,
                title = window.title,
                space_id = space_id,
                frame = window.frame,
            })
        end
    end
    return kept
end

return server_windows
