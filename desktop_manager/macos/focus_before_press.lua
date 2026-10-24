local read_desktops = require("desktop_manager.macos.read_desktops")
local track_windows = require("desktop_manager.macos.track_windows")

---Finds the window to focus before a press on the thumbnail of a desktop, so that the application
---of the chosen window is the frontmost application when the press ends, as the README says under
---the limits of Hammerspoon and macOS 27.0.1.
local focus_before_press = {}

---The window that a press of the list or the search brings to the front.
---@class ChosenWindow
---@field bundle_id string the bundle id of the application of the window
---@field window_id integer

---@param window table an hs.window
---@return ChosenWindow
function focus_before_press.choose(window)
    return { bundle_id = track_windows.bundle_id_of(window:application()), window_id = window:id() }
end

---The window to focus before the press that shows the desktop, or nil when the press needs no
---focus.
---The press needs the focus when the application of the chosen window runs, is not hidden and is
---not the frontmost application, and its focused window, or else its main window, is a standard
---window other than the chosen window, on the desktop that shows on the screen of the desktop to
---show.
---The checks that need no accessibility come first, so that a press with the application in front
---reads nothing through accessibility.
---@param chosen ChosenWindow
---@param space_id integer the desktop that the press shows
---@return table|nil window an hs.window
function focus_before_press.find_window_to_focus(chosen, space_id)
    local application = track_windows.find_running_application(chosen.bundle_id)
    if not application then
        return nil
    end
    if focus_before_press.is_frontmost(chosen.bundle_id) then
        return nil
    end
    if application:isHidden() then
        return nil
    end
    local window = application:focusedWindow() or application:mainWindow()
    if not window or window:id() == chosen.window_id or not window:isStandard() then
        return nil
    end
    local screen_uuid = read_desktops.find_screen_uuid_of_any_space(space_id)
    local screen_desktops = screen_uuid and read_desktops.find_screen_desktops(screen_uuid)
    if
        not screen_desktops
        or read_desktops.find_window_space_id(window:id()) ~= screen_desktops.active_space_id
    then
        return nil
    end
    return window
end

---@param bundle_id string
---@return boolean whether the application of the bundle id is the frontmost application
function focus_before_press.is_frontmost(bundle_id)
    local frontmost = hs.application.frontmostApplication()
    return frontmost ~= nil and track_windows.bundle_id_of(frontmost) == bundle_id
end

return focus_before_press
