local default_settings = require("desktop_manager.default_settings")
local expect = require("tests.expect")

local SETTINGS_MODULE_NAME = "desktop_manager.default_settings"

---Runs a generator of `tools/` from the repository root, with the settings of
---`desktop_manager/default_settings.lua` under another `url_event_name`.
---@param generator_path string
---@param output_path string the argument of the generator
---@param url_event_name string
local function run_generator_with_url_event_name(generator_path, output_path, url_event_name)
    local command_arguments = arg
    package.loaded[SETTINGS_MODULE_NAME] = {
        create = function(state_file_path)
            local settings = default_settings.create(state_file_path)
            settings.url_event_name = url_event_name
            return settings
        end,
    }
    arg = { [0] = generator_path, output_path } -- luacheck: ignore 121
    local is_run, message = pcall(dofile, generator_path)
    arg = command_arguments -- luacheck: ignore 121
    package.loaded[SETTINGS_MODULE_NAME] = default_settings
    if not is_run then
        error(message, 0)
    end
end

---@param command string
---@return string[] the lines that the command prints
local function read_command_lines(command)
    local output = io.popen(command)
    if not output then
        error(string.format("%s did not start", command))
    end
    local lines = {}
    for line in output:lines() do
        table.insert(lines, line)
    end
    output:close()
    return lines
end

---@param path string
---@return string
local function read_file(path)
    local file = io.open(path)
    if not file then
        error(string.format("%s cannot be read", path))
    end
    local text = file:read("a")
    file:close()
    return text
end

return {
    the_launcher_scripts_open_the_urls_of_the_setting_url_event_name = function()
        local folder = read_command_lines("mktemp -d")[1]
        local is_checked, message = pcall(function()
            run_generator_with_url_event_name(
                "tools/write_launcher_scripts.lua",
                folder,
                "desktops"
            )
            local file_names = read_command_lines(string.format("ls '%s'", folder))
            expect.equal(#file_names > 20, true)
            for _, file_name in ipairs(file_names) do
                local text = read_file(folder .. "/" .. file_name)
                local opens_the_url = text:find('open -g "hammerspoon://desktops?', 1, true) ~= nil
                expect.equal({ file_name, opens_the_url }, { file_name, true })
                expect.equal({ file_name, text:find("desktop-manager", 1, true) }, { file_name })
            end
        end)
        os.execute(string.format("rm -rf '%s'", folder))
        if not is_checked then
            error(message, 0)
        end
    end,

    the_settings_of_the_asyar_extension_hold_the_setting_url_event_name = function()
        local path = os.tmpname()
        local is_checked, message = pcall(function()
            run_generator_with_url_event_name(
                "tools/write_asyar_extension_settings.lua",
                path,
                "desktops"
            )
            expect.equal(read_file(path):find('"urlEventName": "desktops"', 1, true) ~= nil, true)
        end)
        os.remove(path)
        if not is_checked then
            error(message, 0)
        end
    end,
}
