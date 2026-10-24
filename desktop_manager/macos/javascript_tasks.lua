---Starts the scripts of JavaScript for Automation in this folder through `osascript`, which runs
---them in a process of their own with the permissions of Hammerspoon, such as the permission for
---Screen Recording.
local javascript_tasks = {}

local OSASCRIPT_PATH = "/usr/bin/osascript"
local SCRIPT_FOLDER = (
    debug.getinfo(1, "S").source:match("^@(.*/desktop_manager/macos)/javascript_tasks%.lua$")
    or "./desktop_manager/macos"
)

---Creates the task of a script, which the caller starts.
---On macOS 27.0.1, the output of a task stopped at 64 KiB, and the task with it, unless
---`hs.task.new` received a streaming callback, and a callback set later did not help.
---@param script_name string a script of this folder, such as "list_server_windows.js"
---@param script_arguments string[]
---@param on_exit fun(exit_code: integer, output: string, error_output: string)
---@param on_output fun(task: table|nil, output: string, error_output: string): boolean|nil receives
---the output as it comes, or nil to receive the whole output at the exit
---@return table|nil the hs.task, or nil when Hammerspoon cannot create it
function javascript_tasks.new(script_name, script_arguments, on_exit, on_output)
    local arguments = { "-l", "JavaScript", SCRIPT_FOLDER .. "/" .. script_name }
    for _, argument in ipairs(script_arguments) do
        table.insert(arguments, argument)
    end
    if on_output then
        return hs.task.new(OSASCRIPT_PATH, on_exit, on_output, arguments)
    end
    return hs.task.new(OSASCRIPT_PATH, on_exit, arguments)
end

return javascript_tasks
