---Runs the AppleScript of a command of the trash tool when the URL
---`hammerspoon://<url_event_name>?command=<command id>` arrives, as the Asyar extension in
---`asyar-trash/` opens it.
---The script runs in a task of `osascript`, because the confirmation of Empty Trash may wait for
---the user for up to a day, and a script inside Hammerspoon would block it meanwhile.
local trash_commands = require("trash.core.trash_commands")

local trash_controller = {}

local OSASCRIPT_PATH = "/usr/bin/osascript"
local SCRIPT_FOLDER = (
    debug.getinfo(1, "S").source:match("^@(.*/trash/macos)/trash_controller%.lua$")
    or "./trash/macos"
)

---@class TrashController
---@field log table an hs.logger, whose lines show in the Hammerspoon console
---@field running_command_ids table<string, boolean> the commands whose script runs, because two
---runs of Empty Trash at once could leave the warning of the Finder off
local TrashController = {}
TrashController.__index = TrashController

---@param report TrashReport
function TrashController:show_report(report)
    local line = string.format("%s: %s", report.title, report.message)
    if report.is_failure then
        self.log.w(line)
    else
        self.log.i(line)
    end
    if report.is_notified then
        hs.notify.new({ title = report.title, informativeText = report.message }):send()
    end
end

---@param params table<string, string>
function TrashController:run_url_command(params)
    local command_id = params.command
    local command = trash_commands.BY_ID[command_id]
    if not command then
        self:show_report(trash_commands.report_unknown_command(command_id))
        return
    end
    if self.running_command_ids[command_id] then
        self:show_report(trash_commands.report_command_running(command))
        return
    end
    local task = hs.task.new(OSASCRIPT_PATH, function(exit_code, output, error_output)
        self.running_command_ids[command_id] = nil
        self:show_report(trash_commands.report_script_end(command, exit_code, output, error_output))
    end, { SCRIPT_FOLDER .. "/" .. command.script_name })
    self.running_command_ids[command_id] = true
    if not task or not task:start() then
        self.running_command_ids[command_id] = nil
        self:show_report(trash_commands.report_start_failure(command))
    end
end

---@param settings TrashSettings
---@return TrashController
function trash_controller.start(settings)
    local controller = setmetatable({
        log = hs.logger.new("trash", "info"),
        running_command_ids = {},
    }, TrashController)
    hs.urlevent.bind(settings.url_event_name, function(_, params)
        controller:run_url_command(params)
    end)
    return controller
end

return trash_controller
