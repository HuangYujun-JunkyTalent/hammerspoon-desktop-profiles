# Requirements of the desktop and window manager built on Hammerspoon

The overall objective is a quick Workspace switcher that manages windows and desktops (Spaces) on macOS.

## Versions of macOS and Hammerspoon that the tool supports

No strict requirements, but it should work with my current versions of macOS and Hammerspoon.

## Workspace definition and management

Here a workspace is the number of desktops (Spaces) and the windows that are open on each desktop.
The tool lets the user activate or deactivate workspace profiles.

When no workspace profile is active, everything is managed by the default macOS window manager.

When a workspace profile is active, the tool remembers the desktop and window configuration and restores it when the profile is activated again.

Workspaces have numbers, and the user can rename them.

When the user switches from one profile to another, the tool minimizes the windows of the profile left.
A setting makes the tool hide an application instead when all its windows belong to profiles other than the active one.
A window of another profile that the user brings back by hand, from the Dock or by unhiding its application, stays in sight and keeps its profile.
A window opened while a profile is active joins that profile.

When a saved window belongs to an application that is not running, activating the profile launches the application.
The tool then places each window of the application as it appears, matched by application and title.

## Multiple monitor behavior

Each profile manages the desktops and windows on all monitor setups that have been seen.
When monitor configurations change to a remembered configuration, the tool restores the remembered desktop and window configuration.

When monitor configurations change to a new configuration, the tool keeps the current profile active, but let OS automatically manage the desktops and windows.

The user should be able to switch between level of definitions of "the same monitor configuration".
For instance, I like to have at least:

1. One mode, where "internal monitor only", "internal monitor + <x> external monitors", "<x> external monitors only" are different monitor configurations, but different external monitor types and names are not relevant.
2. Another mode, where every external monitor type and name is relevant, so "internal monitor + external monitor A" and "internal monitor + external monitor B" are different monitor configurations.

## Desktop operations that work around Hammerspoon on macOS 27.0.1

Hammerspoon 1.1.1 on macOS 27.0.1 reads the desktops and the windows on them, but fails to move a window to another desktop and to switch, add or remove desktops.
The issues https://github.com/Hammerspoon/hammerspoon/issues/3903 and https://github.com/Hammerspoon/hammerspoon/issues/3897 report the failures, read on 2026-10-10.

The tool switches desktops with the macOS shortcuts Control-1 to Control-9, which the user turns on in System Settings.
The tool moves a window to another desktop by minimizing it, switching to the target desktop and unminimizing it.
The tool leaves out a simulated drag of the title bar, because a drag at a fixed point can pull a tab out of a browser window.
The tool adds and removes desktops through the accessibility tree of Mission Control, which macOS 27 keeps under the process `WindowManager`.
When adding or removing a desktop fails, the tool notifies the user.
One module holds these operations, so that it can be replaced once Hammerspoon works on macOS 27 again.

## Shortcuts

It'a better to develop a asyar (compatible with raycast) plugin that can be used to switch between workspace profiles.
For keyboard shortcuts, the idea is to use number keys to activate, deactivate, and switch between workspace profiles.
Let's find a nice keyboard shortcut.

Each shortcut is a combination of modifier keys with a number key.
The modifiers with a number from 1 to 9 activate the profile of that number, or switch to it from another profile.
The same keys on the active profile deactivate it.
The modifiers with 0 deactivate the active profile.
The modifiers are a setting, and their default is Command-Option-Shift.

The plugin for Asyar is a set of shell scripts.
Each script carries the headers `@asyar.*` that the Scripts extension of Asyar reads and the headers `@raycast.*` that Raycast reads, so both launchers run it.
Each script opens a URL `hammerspoon://...` that the tool binds.

## Development practices that the project follows

The code is Lua 5.4, the version that Hammerspoon 1.1.1 embeds.
The core that decides what to save and restore calls no Hammerspoon function, and unit tests run it with `lua` 5.4 outside Hammerspoon.
A separate module moves the windows and changes the desktops on macOS.
`luacheck` lints the code and `stylua` formats it, with their settings in the repository.
Changes are committed in small steps to the local repository, and nothing is pushed.
Hammerspoon loads the tool through a one-line `~/.hammerspoon/init.lua` that loads the `init.lua` of the repository.
The user runs the tests that move windows, on the user's own machine.
