#!/bin/sh
# Turns off one macOS shortcut of System Settings, Keyboard, Keyboard Shortcuts, and keeps its keys,
# so that turning it on again in System Settings brings back the same shortcut.
# The window "Keyboard shortcuts…" of the desktop manager runs it when the user chooses to turn off
# a macOS shortcut that a shortcut of the tools would collide with.
#
# Usage: disable_macos_shortcut.sh <id> <character> <key code> <flags> [domain]
# The id is the number of the entry in AppleSymbolicHotKeys, and the domain defaults to
# com.apple.symbolichotkeys, while a path to a plist file serves for a test.
set -eu

if [ "$#" -lt 4 ]; then
    echo "usage: $0 <id> <character> <key code> <flags> [domain]" >&2
    exit 2
fi
id="$1"
character="$2"
key_code="$3"
flags="$4"
domain="${5:-com.apple.symbolichotkeys}"

defaults write "$domain" AppleSymbolicHotKeys -dict-add "$id" \
    "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>$character</integer><integer>$key_code</integer><integer>$flags</integer></array><key>type</key><string>standard</string></dict></dict>"

if [ "$domain" = "com.apple.symbolichotkeys" ]; then
    # Applies the change without a new login.
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
fi
echo "The macOS shortcut $id is off in $domain"
