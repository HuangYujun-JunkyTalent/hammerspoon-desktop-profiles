std = "lua54"
max_line_length = 100
read_globals = { "hs" }
globals = { "desktop_manager" }

files["desktop_manager/core"] = { new_read_globals = {} }
files["tests"] = { new_read_globals = {} }
