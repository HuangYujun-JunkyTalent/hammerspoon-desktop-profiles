---Writes the launcher scripts that Asyar and Raycast run, one executable file per action.
---Run it from the repository root: lua tools/write_launcher_scripts.lua <output folder>
---Asyar and Raycast give a script one fixed title, so each profile gets scripts of its own.
local default_settings = require("desktop_manager.default_settings")

local GENERATOR_PATH = "tools/write_launcher_scripts.lua"
local URL_PREFIX = "hammerspoon://desktop-manager?"
local ICON = "🖥️"
local PACKAGE_NAME = "Desktop Manager"
local UNUSED_STATE_FILE_PATH = ""

---@class LauncherScript
---@field file_name string
---@field title string
---@field raycast_arguments string[] the JSON of each argument, in order
---@field asyar_arguments string[] the JSON of each argument, in order
---@field body string[] the lines of shell after the headers

---@param query string
---@return string[]
local function open_url_body(query)
    return { string.format('open -g "%s%s"', URL_PREFIX, query) }
end

---@param file_name string
---@param title string
---@param query string
---@return LauncherScript
local function url_script(file_name, title, query)
    return {
        file_name = file_name,
        title = title,
        raycast_arguments = {},
        asyar_arguments = {},
        body = open_url_body(query),
    }
end

---@param profile_count integer
---@return string the JSON list of the profile numbers, for a dropdown
local function profile_dropdown_data(profile_count)
    local items = {}
    for number = 1, profile_count do
        table.insert(items, string.format('{ "title": "%d", "value": "%d" }', number, number))
    end
    return "[" .. table.concat(items, ", ") .. "]"
end

---@param profile_count integer
---@return LauncherScript
local function rename_script(profile_count)
    local data = profile_dropdown_data(profile_count)
    return {
        file_name = "rename-profile.sh",
        title = "Rename Profile",
        raycast_arguments = {
            string.format('{ "type": "dropdown", "placeholder": "Profile", "data": %s }', data),
            '{ "type": "text", "placeholder": "New name" }',
        },
        asyar_arguments = {
            string.format(
                '{ "name": "profile", "type": "dropdown", "default": "1", "data": %s }',
                data
            ),
            '{ "name": "name", "type": "text", "placeholder": "New name", "required": true }',
        },
        body = {
            "encoded_name=$(osascript -l JavaScript"
                .. " -e 'function run(argv) { return encodeURIComponent(argv[0]) }' \"$2\")",
            'open -g "' .. URL_PREFIX .. 'action=rename&profile=$1&name=$encoded_name"',
        },
    }
end

---@param profile_count integer
---@return LauncherScript[]
local function list_scripts(profile_count)
    local scripts = {}
    for number = 1, profile_count do
        table.insert(
            scripts,
            url_script(
                string.format("activate-profile-%d.sh", number),
                string.format("Activate Profile %d", number),
                string.format("action=activate&profile=%d", number)
            )
        )
        table.insert(
            scripts,
            url_script(
                string.format("deactivate-profile-%d.sh", number),
                string.format("Deactivate Profile %d", number),
                string.format("action=deactivate&profile=%d", number)
            )
        )
    end
    table.insert(
        scripts,
        url_script("deactivate-active-profile.sh", "Deactivate Active Profile", "action=deactivate")
    )
    table.insert(scripts, rename_script(profile_count))
    table.insert(
        scripts,
        url_script(
            "cycle-profile-monitor-matching.sh",
            "Cycle Profile Monitor Matching",
            "action=cycle-monitor-matching"
        )
    )
    table.insert(
        scripts,
        url_script("save-profile-arrangement.sh", "Save Profile Arrangement", "action=save")
    )
    return scripts
end

---Asyar reads the header block up to the first line that is not a comment, and Raycast reads its
---headers from any comment line.
---@param script LauncherScript
---@return string
local function render(script)
    local lines = {
        "#!/bin/bash",
        "# @raycast.schemaVersion 1",
        "# @raycast.title " .. script.title,
        "# @raycast.mode silent",
        "# @raycast.packageName " .. PACKAGE_NAME,
        "# @raycast.icon " .. ICON,
    }
    for index, argument in ipairs(script.raycast_arguments) do
        table.insert(lines, string.format("# @raycast.argument%d %s", index, argument))
    end
    table.insert(lines, "# @asyar.title " .. script.title)
    table.insert(lines, "# @asyar.icon " .. ICON)
    table.insert(lines, "# @asyar.mode silent")
    for index, argument in ipairs(script.asyar_arguments) do
        table.insert(lines, string.format("# @asyar.argument:%d %s", index, argument))
    end
    table.insert(lines, "")
    table.insert(lines, "# Written by " .. GENERATOR_PATH .. ".")
    table.insert(lines, "# Change the generator and run make launcher-scripts to change this file.")
    for _, line in ipairs(script.body) do
        table.insert(lines, line)
    end
    return table.concat(lines, "\n") .. "\n"
end

---@param folder string
---@param script LauncherScript
local function write_script(folder, script)
    local path = folder .. "/" .. script.file_name
    local file, open_error = io.open(path, "w")
    if not file then
        error(string.format("%s cannot be written: %s", path, tostring(open_error)), 0)
    end
    file:write(render(script))
    file:close()
    if not os.execute(string.format("chmod +x '%s'", path)) then
        error(string.format("%s could not be made executable", path), 0)
    end
end

local output_folder = arg[1]
if not output_folder then
    error("the output folder is missing: lua " .. GENERATOR_PATH .. " <output folder>", 0)
end
local profile_count = default_settings.create(UNUSED_STATE_FILE_PATH).profile_count
for _, script in ipairs(list_scripts(profile_count)) do
    write_script(output_folder, script)
end
