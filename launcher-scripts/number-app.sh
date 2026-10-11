#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Number App
# @raycast.mode silent
# @raycast.packageName Desktop Manager
# @raycast.icon 🖥️
# @raycast.argument1 { "type": "dropdown", "placeholder": "Number", "data": [{ "title": "1", "value": "1" }, { "title": "2", "value": "2" }, { "title": "3", "value": "3" }, { "title": "4", "value": "4" }, { "title": "5", "value": "5" }, { "title": "6", "value": "6" }, { "title": "7", "value": "7" }, { "title": "8", "value": "8" }, { "title": "9", "value": "9" }] }
# @raycast.argument2 { "type": "text", "placeholder": "Running app" }
# @asyar.title Number App
# @asyar.icon 🖥️
# @asyar.mode silent
# @asyar.argument:1 { "name": "number", "type": "dropdown", "default": "1", "required": true, "data": [{ "title": "1", "value": "1" }, { "title": "2", "value": "2" }, { "title": "3", "value": "3" }, { "title": "4", "value": "4" }, { "title": "5", "value": "5" }, { "title": "6", "value": "6" }, { "title": "7", "value": "7" }, { "title": "8", "value": "8" }, { "title": "9", "value": "9" }] }
# @asyar.argument:2 { "name": "app", "type": "text", "placeholder": "Running app", "required": true }

# Written by tools/write_launcher_scripts.lua.
# Change the generator and run make launcher-scripts to change this file.
encoded_app=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "$2")
open -g "hammerspoon://desktop-manager?action=number-app&number=$1&app=$encoded_app"
