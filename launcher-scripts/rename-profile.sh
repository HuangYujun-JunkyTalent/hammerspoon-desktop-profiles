#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Rename Profile
# @raycast.mode silent
# @raycast.packageName Desktop Manager
# @raycast.icon 🖥️
# @raycast.argument1 { "type": "dropdown", "placeholder": "Profile", "data": [{ "title": "1", "value": "1" }, { "title": "2", "value": "2" }, { "title": "3", "value": "3" }, { "title": "4", "value": "4" }, { "title": "5", "value": "5" }, { "title": "6", "value": "6" }, { "title": "7", "value": "7" }, { "title": "8", "value": "8" }, { "title": "9", "value": "9" }] }
# @raycast.argument2 { "type": "text", "placeholder": "New name" }
# @asyar.title Rename Profile
# @asyar.icon 🖥️
# @asyar.mode silent
# @asyar.argument:1 { "name": "profile", "type": "dropdown", "default": "1", "data": [{ "title": "1", "value": "1" }, { "title": "2", "value": "2" }, { "title": "3", "value": "3" }, { "title": "4", "value": "4" }, { "title": "5", "value": "5" }, { "title": "6", "value": "6" }, { "title": "7", "value": "7" }, { "title": "8", "value": "8" }, { "title": "9", "value": "9" }] }
# @asyar.argument:2 { "name": "name", "type": "text", "placeholder": "New name", "required": true }

# Written by tools/write_launcher_scripts.lua.
# Change the generator and run make launcher-scripts to change this file.
encoded_name=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "$2")
open -g "hammerspoon://desktop-manager?action=rename&profile=$1&name=$encoded_name"
