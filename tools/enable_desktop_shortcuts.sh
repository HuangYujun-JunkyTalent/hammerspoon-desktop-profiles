#!/bin/sh
# Turns on the macOS shortcuts "Switch to Desktop 1" to "Switch to Desktop 10" as Control-1 to
# Control-9 and Control-0, which the desktop manager presses to switch desktops, and keeps every
# other shortcut.
# System Settings lists the shortcut of a desktop only while the desktop exists, and the desktops of
# all screens share one sequence, so a desktop that an external monitor adds can lack its shortcut.
#
# Usage: enable_desktop_shortcuts.sh [domain]
# The domain defaults to com.apple.symbolichotkeys, and a path to a plist file serves for a test.
set -eu

domain="${1:-com.apple.symbolichotkeys}"
control_flag=262144
number=1
# The key codes of the keys 1 to 9 and 0 of an ANSI keyboard, in order.
for key_code in 18 19 20 21 23 22 26 28 25 29; do
    defaults write "$domain" AppleSymbolicHotKeys -dict-add "$((117 + number))" \
        "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>$key_code</integer><integer>$control_flag</integer></array><key>type</key><string>standard</string></dict></dict>"
    number=$((number + 1))
done

if [ "$domain" = "com.apple.symbolichotkeys" ]; then
    # Applies the shortcuts without a new login.
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
fi
echo "Switch to Desktop 1 to 10 are on as Control-1 to Control-9 and Control-0 in $domain"
