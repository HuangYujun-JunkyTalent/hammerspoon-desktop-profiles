#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Release App Number
# @raycast.mode silent
# @raycast.packageName Desktop Manager
# @raycast.icon 🖥️
# @raycast.argument1 { "type": "dropdown", "placeholder": "Number", "data": [{ "title": "1", "value": "1" }, { "title": "2", "value": "2" }, { "title": "3", "value": "3" }, { "title": "4", "value": "4" }, { "title": "5", "value": "5" }, { "title": "6", "value": "6" }, { "title": "7", "value": "7" }, { "title": "8", "value": "8" }, { "title": "9", "value": "9" }] }
# @asyar.title Release App Number
# @asyar.icon 🖥️
# @asyar.mode silent
# @asyar.argument:1 { "name": "number", "type": "dropdown", "default": "1", "required": true, "data": [{ "title": "1", "value": "1" }, { "title": "2", "value": "2" }, { "title": "3", "value": "3" }, { "title": "4", "value": "4" }, { "title": "5", "value": "5" }, { "title": "6", "value": "6" }, { "title": "7", "value": "7" }, { "title": "8", "value": "8" }, { "title": "9", "value": "9" }] }

# Written by tools/write_launcher_scripts.lua.
# Change the generator and run make launcher-scripts to change this file.
open -g "hammerspoon://desktop-manager?action=release-app-number&number=$1"
