local missing_windows = require("desktop_manager.core.missing_windows")
local new_windows = require("desktop_manager.macos.new_windows")
local profile_state = require("desktop_manager.core.profile_state")
local read_desktops = require("desktop_manager.macos.read_desktops")
local unmatched_window_action = require("desktop_manager.core.unmatched_window_action")

---Opens a new window for each record in sight of a switch whose window no longer exists, under
---`unmatched_window_action`.
local open_missing_windows = {}

---@class NewWindowsContext
---@field timing Timing
---@field log table an hs.logger
---@field read_monitor_configuration fun(): MonitorConfiguration
---@field continue fun(callback: function): function wraps a callback of a step, so that the
---callback does nothing once the watchdog has stopped the switch
---@field action string a value of unmatched_window_action

---The windows that a switch opened for its missing records.
---@class NewWindowsResult
---@field failures string[]
---@field new_matches WindowMatch[] the records and their new windows, which the restore moves to
---their recorded places
---@field renames WindowRename[] the new window ids of the records that had a window id

---Gives each record in sight whose window no longer exists a new window of its application.
---A new window opens on the desktop that shows, and the restore moves it to its recorded desktop
---by its frame and its id, through the new matches that `on_done` receives.
---Under `unmatched_window_action.FORGET`, no window opens, and the update after the switch drops
---the records.
---A record whose window sits on a desktop that Hammerspoon has not seen keeps that window.
---@param number integer the profile of the switch
---@param unmatched_records WindowRecord[]
---@param context NewWindowsContext
---@param on_done fun(result: NewWindowsResult)
function open_missing_windows.open_all(number, unmatched_records, context, on_done)
    local missing_records = {}
    local classified =
        missing_windows.classify_unmatched(unmatched_records, read_desktops.find_window_space_id)
    for _, classified_record in ipairs(classified) do
        local record = classified_record.record
        if classified_record.kind == missing_windows.UNMATCHED_KIND.OUT_OF_SIGHT then
            context.log.f(
                "%s window %q is recorded out of sight and gone",
                record.app_name,
                record.title
            )
        elseif classified_record.kind == missing_windows.UNMATCHED_KIND.ON_UNSEEN_DESKTOP then
            context.log.f(
                "%s window %q stays on desktop %d, where Hammerspoon has not seen it",
                record.app_name,
                record.title,
                classified_record.space_id
            )
        else
            table.insert(missing_records, record)
        end
    end
    if context.action == unmatched_window_action.FORGET then
        for _, record in ipairs(missing_records) do
            context.log.f(
                "profile %d: %s window %q is gone, and the profile forgets it",
                number,
                record.app_name,
                record.title
            )
        end
        on_done({ failures = {}, new_matches = {}, renames = {} })
        return
    end
    local plan = missing_windows.plan(
        missing_records,
        context.read_monitor_configuration(),
        read_desktops.read_desktop_layout()
    )
    for _, record in ipairs(plan.unplaced_records) do
        context.log.f("%s window %q has no recorded desktop here", record.app_name, record.title)
    end
    local session = new_windows.start_session(context.timing)
    local failures, renames, new_matches = {}, {}, {}
    local function open_next(index)
        local missing_window = plan.missing_windows[index]
        if not missing_window then
            on_done({ failures = failures, new_matches = new_matches, renames = renames })
            return
        end
        local record = missing_window.record
        session:provide_window(
            record,
            context.continue(function(window, error_message)
                if not window then
                    table.insert(failures, error_message)
                else
                    context.log.f(
                        "profile %d: %s window %q is now window %d",
                        number,
                        record.app_name,
                        record.title,
                        window:id()
                    )
                    table.insert(new_matches, { window_id = window:id(), record = record })
                    if record.window_id then
                        table.insert(renames, profile_state.rename_of(record, window:id()))
                    end
                end
                open_next(index + 1)
            end)
        )
    end
    open_next(1)
end

return open_missing_windows
