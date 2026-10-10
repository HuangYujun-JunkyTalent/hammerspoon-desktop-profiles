#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Switch Desktop Profile
# @raycast.mode silent
# @raycast.packageName Desktop Manager
# @raycast.icon 🖥️
# @raycast.argument1 { "type": "dropdown", "placeholder": "Profile", "data": [{ "title": "1", "value": "1" }, { "title": "2", "value": "2" }, { "title": "3", "value": "3" }, { "title": "4", "value": "4" }, { "title": "5", "value": "5" }, { "title": "6", "value": "6" }, { "title": "7", "value": "7" }, { "title": "8", "value": "8" }, { "title": "9", "value": "9" }] }
# @asyar.title Switch Desktop Profile
# @asyar.icon 🖥️
# @asyar.mode silent
# @asyar.argument:1 { "name": "profile", "type": "dropdown", "default": "1", "data": [{ "title": "1", "value": "1" }, { "title": "2", "value": "2" }, { "title": "3", "value": "3" }, { "title": "4", "value": "4" }, { "title": "5", "value": "5" }, { "title": "6", "value": "6" }, { "title": "7", "value": "7" }, { "title": "8", "value": "8" }, { "title": "9", "value": "9" }] }

open -g "hammerspoon://desktop-manager?action=activate&profile=$1"
