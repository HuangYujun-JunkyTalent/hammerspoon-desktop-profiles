---Writes the settings of `window_tiling/default_settings.lua` that the Asyar extension of the
---window tiling needs, so that the extension holds no copy of them.
---Run it from the repository root: lua tools/write_asyar_window_tiling_settings.lua <output file>
local default_settings = require("window_tiling.default_settings")

local GENERATOR_PATH = "tools/write_asyar_window_tiling_settings.lua"

local output_path = arg[1]
if not output_path then
    error("the output file is missing: lua " .. GENERATOR_PATH .. " <output file>", 0)
end
local settings = default_settings.create()
local file, open_error = io.open(output_path, "w")
if not file then
    error(string.format("%s cannot be written: %s", output_path, tostring(open_error)), 0)
end
file:write(
    string.format(
        '{\n  "generatedBy": "%s",\n  "urlEventName": "%s"\n}\n',
        GENERATOR_PATH,
        settings.url_event_name
    )
)
file:close()
