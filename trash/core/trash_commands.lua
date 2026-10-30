---The commands of the trash tool, the AppleScript that runs each, and what the end of a script
---reports.
local trash_commands = {}

---@class TrashCommand
---@field title string the name of the item in Asyar, which titles the reports of the command
---@field script_name string a script of `trash/macos/`

---The commands by the ids of the items of `asyar-trash/manifest.json`.
---@type table<string, TrashCommand>
trash_commands.BY_ID = {
    trash = { title = "Trash", script_name = "open_trash.applescript" },
    ["empty-trash"] = { title = "Empty Trash", script_name = "empty_trash.applescript" },
}

---The output of the script of Empty Trash when the Trash held nothing.
local EMPTY_TRASH_OUTPUT = "empty"

---@class TrashReport
---@field title string
---@field message string the line of the console, and the body of the notification when
---`is_notified`
---@field is_failure boolean
---@field is_notified boolean

---@param text string
---@return string
local function trim_blanks(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

---The message of an error that `osascript` writes for a script file, which comes after the path of
---the file and the range of the failing text, as in
---`/path/empty_trash.applescript:95:105: execution error: <message> (<number>)`.
---@param error_output string
---@return string
function trash_commands.read_osascript_error(error_output)
    local text = trim_blanks(error_output)
    if text == "" then
        return "osascript failed without a message."
    end
    return text:match("execution error: (.+)$") or text
end

---@param command TrashCommand
---@param exit_code integer
---@param output string what the script printed, such as "emptied"
---@param error_output string
---@return TrashReport
function trash_commands.report_script_end(command, exit_code, output, error_output)
    if exit_code ~= 0 then
        return {
            title = command.title .. " failed",
            message = trash_commands.read_osascript_error(error_output),
            is_failure = true,
            is_notified = true,
        }
    end
    local outcome = trim_blanks(output)
    if outcome == EMPTY_TRASH_OUTPUT then
        return {
            title = command.title,
            message = "The Trash is empty.",
            is_failure = false,
            is_notified = true,
        }
    end
    return { title = command.title, message = outcome, is_failure = false, is_notified = false }
end

---@param command_id string|nil
---@return TrashReport
function trash_commands.report_unknown_command(command_id)
    return {
        title = "Trash tool",
        message = string.format("The command %q is unknown.", tostring(command_id)),
        is_failure = true,
        is_notified = true,
    }
end

---@param command TrashCommand
---@return TrashReport
function trash_commands.report_command_running(command)
    return {
        title = command.title,
        message = command.title .. " is already running.",
        is_failure = false,
        is_notified = true,
    }
end

---@param command TrashCommand
---@return TrashReport
function trash_commands.report_start_failure(command)
    return {
        title = command.title .. " failed",
        message = "Hammerspoon could not start osascript.",
        is_failure = true,
        is_notified = true,
    }
end

return trash_commands
