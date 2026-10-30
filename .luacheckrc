std = "lua54"
max_line_length = 100
read_globals = { "hs" }
globals = { "desktop_manager", "window_tiler" }

files["desktop_manager/core"] = { new_read_globals = {} }
files["window_tiling/core"] = { new_read_globals = {} }
files["keyboard_shortcuts/core"] = { new_read_globals = {} }
files["trash/core"] = { new_read_globals = {} }
files["tests"] = { new_read_globals = {} }
files["tests/fake_hammerspoon.lua"] = { new_read_globals = { "hs" }, self = false }
files["type_definitions"] = { globals = { "hs" }, unused = false }
