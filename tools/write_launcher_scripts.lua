---Writes the launcher scripts that Asyar and Raycast run, one executable file per action.
---Run it from the repository root: lua tools/write_launcher_scripts.lua <output folder>
---Asyar and Raycast give a script one fixed title, so each profile gets scripts of its own.
local default_settings = require("desktop_manager.default_settings")

local GENERATOR_PATH = "tools/write_launcher_scripts.lua"
local ICON = "🖥️"
local PACKAGE_NAME = "Desktop Manager"
local UNUSED_STATE_FILE_PATH = ""

---@class LauncherScript
---@field file_name string
---@field title string
---@field raycast_arguments string[] the JSON of each argument, in order
---@field asyar_arguments string[] the JSON of each argument, in order
---@field body string[] the lines of shell after the headers

---@param url_event_name string the host of the URLs of the desktop manager
---@return string the start of every URL of the desktop manager, up to the query
local function build_url_prefix(url_event_name)
    return string.format("hammerspoon://%s?", url_event_name)
end

---@param url_prefix string
---@param file_name string
---@param title string
---@param query string
---@return LauncherScript
local function url_script(url_prefix, file_name, title, query)
    return {
        file_name = file_name,
        title = title,
        raycast_arguments = {},
        asyar_arguments = {},
        body = { string.format('open -g "%s%s"', url_prefix, query) },
    }
end

---@param count integer
---@return string the JSON list of the numbers from 1 to the count, for a dropdown
local function number_dropdown_data(count)
    local items = {}
    for number = 1, count do
        table.insert(items, string.format('{ "title": "%d", "value": "%d" }', number, number))
    end
    return "[" .. table.concat(items, ", ") .. "]"
end

---@param asyar_name string the name of the argument in Asyar, such as "profile"
---@param raycast_placeholder string the placeholder of the argument in Raycast, such as "Profile"
---@param count integer
---@return string raycast_argument the JSON of a dropdown of the numbers from 1 to the count
---@return string asyar_argument the JSON of the same dropdown, required, with 1 by default
local function number_dropdown_arguments(asyar_name, raycast_placeholder, count)
    local data = number_dropdown_data(count)
    local raycast_argument = string.format(
        '{ "type": "dropdown", "placeholder": "%s", "data": %s }',
        raycast_placeholder,
        data
    )
    local asyar_argument = string.format(
        '{ "name": "%s", "type": "dropdown", "default": "1", "required": true, "data": %s }',
        asyar_name,
        data
    )
    return raycast_argument, asyar_argument
end

---@param variable string the shell variable that takes the encoded argument
---@param position integer the position of the argument, such as 2 for `$2`
---@return string the line of shell that encodes the argument as a part of a URL into the variable
local function build_argument_encoding_line(variable, position)
    return string.format(
        "%s=$(osascript -l JavaScript"
            .. " -e 'function run(argv) { return encodeURIComponent(argv[0]) }' \"$%d\")",
        variable,
        position
    )
end

---Asyar refuses a required argument after an optional one, and then registers no script of the
---folder, so both arguments are required.
---@param url_prefix string
---@param profile_count integer
---@return LauncherScript
local function rename_script(url_prefix, profile_count)
    local raycast_profile, asyar_profile =
        number_dropdown_arguments("profile", "Profile", profile_count)
    return {
        file_name = "rename-profile.sh",
        title = "Rename Profile",
        raycast_arguments = { raycast_profile, '{ "type": "text", "placeholder": "New name" }' },
        asyar_arguments = {
            asyar_profile,
            '{ "name": "name", "type": "text", "placeholder": "New name", "required": true }',
        },
        body = {
            build_argument_encoding_line("encoded_name", 2),
            'open -g "' .. url_prefix .. 'action=rename&profile=$1&name=$encoded_name"',
        },
    }
end

---@param url_prefix string
---@param app_number_count integer
---@return LauncherScript
local function number_app_script(url_prefix, app_number_count)
    local raycast_number, asyar_number =
        number_dropdown_arguments("number", "Number", app_number_count)
    return {
        file_name = "number-app.sh",
        title = "Number App",
        raycast_arguments = { raycast_number, '{ "type": "text", "placeholder": "Running app" }' },
        asyar_arguments = {
            asyar_number,
            '{ "name": "app", "type": "text", "placeholder": "Running app", "required": true }',
        },
        body = {
            build_argument_encoding_line("encoded_app", 2),
            'open -g "' .. url_prefix .. 'action=number-app&number=$1&app=$encoded_app"',
        },
    }
end

---@param url_prefix string
---@param app_number_count integer
---@return LauncherScript
local function release_app_number_script(url_prefix, app_number_count)
    local raycast_number, asyar_number =
        number_dropdown_arguments("number", "Number", app_number_count)
    return {
        file_name = "release-app-number.sh",
        title = "Release App Number",
        raycast_arguments = { raycast_number },
        asyar_arguments = { asyar_number },
        body = { 'open -g "' .. url_prefix .. 'action=release-app-number&number=$1"' },
    }
end

---@param settings Settings
---@return LauncherScript[]
local function list_scripts(settings)
    local url_prefix = build_url_prefix(settings.url_event_name)
    local scripts = {}
    for number = 1, settings.profile_count do
        table.insert(
            scripts,
            url_script(
                url_prefix,
                string.format("activate-profile-%d.sh", number),
                string.format("Activate Profile %d", number),
                string.format("action=activate&profile=%d", number)
            )
        )
        table.insert(
            scripts,
            url_script(
                url_prefix,
                string.format("deactivate-profile-%d.sh", number),
                string.format("Deactivate Profile %d", number),
                string.format("action=deactivate&profile=%d", number)
            )
        )
    end
    table.insert(
        scripts,
        url_script(
            url_prefix,
            "deactivate-active-profile.sh",
            "Deactivate Active Profile",
            "action=deactivate"
        )
    )
    table.insert(scripts, rename_script(url_prefix, settings.profile_count))
    table.insert(
        scripts,
        url_script(
            url_prefix,
            "cycle-profile-monitor-matching.sh",
            "Cycle Profile Monitor Matching",
            "action=cycle-monitor-matching"
        )
    )
    table.insert(
        scripts,
        url_script(
            url_prefix,
            "save-profile-arrangement.sh",
            "Save Profile Arrangement",
            "action=save"
        )
    )
    table.insert(scripts, number_app_script(url_prefix, settings.app_number_count))
    table.insert(scripts, release_app_number_script(url_prefix, settings.app_number_count))
    return scripts
end

---Asyar reads the header block up to the first line that is not a comment, and Raycast reads its
---headers from any comment line.
---@param script LauncherScript
---@return string
local function build_script_text(script)
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
    file:write(build_script_text(script))
    file:close()
    if not os.execute(string.format("chmod +x '%s'", path)) then
        error(string.format("%s could not be made executable", path), 0)
    end
end

local output_folder = arg[1]
if not output_folder then
    error("the output folder is missing: lua " .. GENERATOR_PATH .. " <output folder>", 0)
end
local settings = default_settings.create(UNUSED_STATE_FILE_PATH)
for _, script in ipairs(list_scripts(settings)) do
    write_script(output_folder, script)
end
