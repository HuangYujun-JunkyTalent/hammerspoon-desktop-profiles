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

A profile holds information on desktops and windows, and a window does not belong to profiles.
For each monitor configuration, a profile records the number of desktops of each screen, the desktop in front, and every window that the tool sees while the profile is active.
The profile records a window as in sight on a desktop with a frame, or as out of sight.
A window is out of sight when it is minimized or its application is hidden.
Activating a profile does the least work that brings back what the profile recorded.
A window already in its recorded state stays as it is.
The tool sets the frame of a window when the frame differs from the recorded one.
A window that another profile recorded and the profile entered did not goes out of sight.
A window that no profile recorded stays as it is, and the profile records it at its next capture.
The tool minimizes a window to take it out of sight.
A setting makes the tool hide an application instead when all its windows go out of sight.
Activating a profile adds the desktops that the profile recorded and a screen lacks.
The tool removes no desktop, because removing a desktop moves the windows on it and changes what the other profiles recorded.

A profile records each window by its application, its window id and its title.
Position and size play no part in the identity, because the tool sets them quickly on the window it takes.
macOS gives a window that its application reopens a new window id.
When a profile is activated and the window of a record in sight no longer exists, a setting chooses one of two options:

- Option a opens a new window of the same application.
- Option b takes an open window of the same application with the same title, and opens a new window when no title matches.

Option b is the default.
The tool opens a new window on the recorded desktop, sets the recorded frame, and the records of every profile then name the new window.
Under option b, the tool also treats an unrecorded window as the reopened copy of a closed recorded window, when both belong to the same application and have the same title.

When a saved window belongs to an application that is not running, the new window comes from a launch of the application.

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
macOS 27.0.1 unminimizes a window onto the desktop it was minimized on, also when another desktop shows, as the log of the tool showed on 2026-10-10.
The tool therefore restores a minimized window where it is, and switches a desktop only to move a window to another screen.
A window on another desktop of its screen stays there, because Hammerspoon and unminimizing both fail to move it.
The console of Hammerspoon notes each such window.
A window moves to another screen when the tool sets its frame there.
The tool leaves out a simulated drag of the title bar, because a drag at a fixed point can pull a tab out of a browser window.
The tool adds desktops through the accessibility tree of Mission Control, which macOS 27 keeps under the process `WindowManager`.
When adding a desktop fails, the tool notifies the user.
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

The plugin for Asyar is an extension of Asyar.
It shows one item per profile, and marks the active profile with a dot.
Running the item of a profile activates it, or deactivates it while it is active.
Another item returns the application numbers of the active profile, or of profile 0, to the default.
The items open the URLs `hammerspoon://...` that the tool binds.

A set of shell scripts stays beside the extension.
Each script carries the headers `@asyar.*` that the Scripts extension of Asyar reads and the headers `@raycast.*` that Raycast reads, so both launchers run it.
Each script opens a URL `hammerspoon://...` that the tool binds.

## Numbers within a profile bring applications to the front

Each profile gives the numbers from 1 to 9 to applications.
While no profile is active, the numbers of profile 0 hold.
Profile 0 keeps numbers alone, so the switches work as before.
A press of Control-Option with a number shows a list of the numbered applications of the active profile, or of profile 0, with their numbers and the titles of their windows.
By default each application is a column, side by side, with its number on top and its windows stacked downward, each a preview with its title under it.
An option groups the columns by display, so that the applications on each display have columns of their own, and another option shows the former rows.
The press selects a window of the application of that number: the window that had the focus last, or the next window when the application is in front.
Each further press of the same number, while Control and Option stay held, selects the next window of that application.
A press of another number selects a window of that application.
Releasing Control or Option brings the selected window to the front, and Escape closes the list without a switch.
A press released at once brings the selected window to the front without the list.
Each application line of the list shows the icon of the application, and each window line shows the icon beside the title.
A setting shows a blurred image of each window in the place of the icon, and the icon stays for a window without an image, such as a minimized one.
Another setting sets how strong the blur is.
Two more settings set the size of a preview and the size of the font of the list, as fractions of the screen in front, and the list follows from them.
By default the list fills the screen properly: the previews and the fonts grow or shrink until the list fills most of the width or the height of the screen, within limits on their growth.
An option keeps the sizes of the settings instead, and shrinks them only until the list fits within the screen.
The columns fold into two lines when two lines give larger previews.
By default a long title flows over up to two lines, and a set number changes the limit.
An option shortens a long title to one line ending in an ellipsis, and another lets the title of the selected window scroll.
The images need the permission for Screen Recording, and they follow one at a time after the list shows.
An image that takes longer than half a second stops the images until the next reload, because the screen capture function of macOS behind them blocked Hammerspoon for two minutes on this machine on 2026-10-10.
The windows are all the windows of the application, also those that the active profile did not record, such as the minimized windows of another profile.
A window on another desktop is reached by showing that desktop.
An application without windows gets a new window, from the same sources that replace a closed window at a switch.

The tool gives the default numbers to the applications that the profile records in sight.
The order follows the screens of the monitor configuration, then the desktops, then the left edges of the windows, so the numbers read from left to right through the desktops.
A default number stays with its application while the profile records a window of it, in sight or out of sight.
The user can give any number to any running application, in the menu bar item or with a launcher script, and the number then stays until the user changes it.
A number that the user returns to the default goes back to the default rule.
Profile 0 gives the default numbers to the applications with a window in sight, in the same order, and a default number stays while its application has a window open.
Control-Option-0 returns every number of the active profile, or of profile 0, to the default, also the numbers that the user gave.
Control-Option-0 does nothing while the list shows.

Control-Option with a free number reaches the application in front unchanged.
A number given to an application takes Control-Option with that number from every other application.
The modifiers are a setting, and their default is Control-Option.
On 2026-10-10, the shortcuts of macOS and the menus of the running applications left Control-Option with a number unused.
Command with a number selects tabs, views and groups in many applications, and Command-Shift with 3, 4 and 5 takes screenshots in macOS.

## Development practices that the project follows

The code is Lua 5.4, the version that Hammerspoon 1.1.1 embeds.
The core that decides what to save and restore calls no Hammerspoon function, and unit tests run it with `lua` 5.4 outside Hammerspoon.
A separate module moves the windows and changes the desktops on macOS.
`luacheck` lints the code and `stylua` formats it, with their settings in the repository.
Changes are committed in small steps to the local repository, and nothing is pushed.
Hammerspoon loads the tool through a one-line `~/.hammerspoon/init.lua` that loads the `init.lua` of the repository.
The user runs the tests that move windows, on the user's own machine.
