# Requirements of the desktop and window manager built on Hammerspoon

The overall objective is a quick Workspace switcher that manages windows and desktops (Spaces) on macOS.

## Versions of macOS and Hammerspoon that the tool supports

No strict requirements, but it should work with my current versions of macOS and Hammerspoon.
The current versions are macOS 27.0.1 and a build of Hammerspoon with pull request #3889, until a release of Hammerspoon holds the pull request.

## Workspace definition and management

Here a workspace is the number of desktops (Spaces) and the windows that are open on each desktop.
The tool lets the user activate or deactivate workspace profiles.

When no workspace profile is active, everything is managed by the default macOS window manager.

When a workspace profile is active, the tool remembers the desktop and window configuration and restores it when the profile is activated again.
After a restart of the Mac or a logout, macOS reopens the windows at the next login with new window ids and at places of its own, and an update would replace the saved layout of the active profile.
The first start of the tool after a login therefore pauses the active profile when it comes within a set time of the login, and a setting gives the time, with 0 turning the pause off.
When the login cannot be read, the time counts from the start of macOS, and only the first start after a start of macOS pauses.
While the profile is paused, no update changes its records or its application numbers, and a change of monitors restores nothing.
The pause lasts across a reload of the tool until the user restores the paused profile, switches to another profile, deactivates the profile, saves its arrangement or clears it.
The shortcut of the paused profile restores its layout as an activation does and ends the pause.
Another profile switches without the update of the paused profile, and the deactivation updates nothing.
The menu bar item and the diagnostics show the pause.

Workspaces have numbers, and the user can rename them.

A profile holds information on desktops and windows, and a window does not belong to profiles.
For each monitor configuration, a profile records the number of desktops of each screen, the desktop that each screen shows, and every window that the tool sees while the profile is active.
A restore shows the recorded desktop on each screen at its end.
The profile records a window as in sight on a desktop with a frame, or as out of sight.
A window is out of sight when it is minimized or its application is hidden.
Activating a profile does the least work that brings back what the profile recorded.
A window already in its recorded state stays as it is.
The tool sets the frame of a window when the frame differs from the recorded one.
A window that another profile recorded and the profile entered did not goes out of sight.
A profile with a layout for the monitor configuration keeps in sight exactly the windows it recorded in sight, so a window that no profile recorded goes out of sight as well.
A profile without a layout leaves in sight the windows that no profile recorded, and records them at its next capture.
The restore after a change of monitors takes no window out of sight.
The tool minimizes a window to take it out of sight.
A setting makes the tool hide an application instead when all its windows go out of sight.
While the tool works, a message on every screen asks the user to wait, so that the user does not move windows or switch desktops while the tool does.
The tool works during a switch, a restore, a change of monitors, an addition or a removal of desktops, a press in Mission Control and the opening of a window.

The user can clear a profile, from the menu or with a keyboard shortcut, which removes the desktops and windows that the profile saved for every monitor configuration, and keeps its name and its application numbers.

The tool manages the windows of every application by default.
The user can instead choose the applications that the tool manages, in one choice for every profile, and macOS keeps managing the windows of the other applications.
The choice has two modes: manage every application except the ticked ones, and manage only the ticked ones.
The user ticks and unticks several applications in one window, which stays open between the ticks.
Activating a profile adds the desktops that the profile recorded and a screen lacks.
After the windows are in place, a restore removes the desktops beyond the number of the profile that are out of view and hold no window that keeps them.
The removal goes from the end of each screen and stops at the first desktop that stays.
A window of an application that the tool leaves to macOS keeps its desktop in every state.
A window of a managed application keeps its desktop only while it is in sight, because macOS moves a minimized window to another desktop when its desktop goes, and the window stays minimized.

A profile records each window by its application, its window id and its title.
Position and size play no part in the identity, because the tool sets them quickly on the window it takes.
A setting chooses what pairs a record with an open window first, the title or the window id.
By default the title decides, the window with the recorded id first among windows with the same title, and the window id decides when no title matches.
macOS gives a window that its application reopens a new window id.
When the window id decides, and the window of a record in sight no longer exists, a second setting chooses one of two options:

- Option a matches the record by its window id alone, so no other window takes it.
- Option b takes an open window of the same application with the same title.

Option b is the default.
The value of each option in the settings names what it matches.
A value that an earlier version gave an option still works, and the console names the value that takes its place.
When no open window takes the record, the third setting below chooses whether the tool opens a new window.
The tool moves a new window to the recorded desktop with the recorded frame, and the records of every profile then name the new window.
Under option b, the tool also treats an unrecorded window as the reopened copy of a closed recorded window, when both belong to the same application and have the same title.

When a saved window belongs to an application that is not running, the new window comes from a launch of the application.

A third setting chooses, under both ways of pairing, what a record in sight gets when no open window matches it.
By default the tool opens a new window, as above.
The other choice opens no window, and the profile forgets the record.

The options of behaviour, such as what a switch does for a recorded window that is gone, change in a settings window while the tool runs, and the menu bar item keeps the quick actions.

## Multiple monitor behavior

Each profile manages the desktops and windows on all monitor setups that have been seen.
When monitor configurations change to a remembered configuration, the tool restores the remembered desktop and window configuration.

When monitor configurations change to a new configuration, the tool keeps the current profile active, but let OS automatically manage the desktops and windows.
An alert then says that the configuration is new to the profile.

When a monitor disconnects, macOS moves its desktops to the end of the built-in display, and gives back only one desktop when the monitor returns, so desktops pile up on the built-in display.
A restore sets each screen to the number of desktops that the profile records for it.
For a monitor configuration that the active profile has no layout for, the tool keeps track of the number of desktops of each display.
The number follows the desktops that the user adds or removes while the monitors stay the same, and the desktops that macOS moves at a change of monitors leave it unchanged.
After a change of monitors to such a configuration, the tool removes the desktops beyond the number of each display by the same rule.

While no profile is active, a change of monitors leaves the desktops and the windows to macOS: the tool moves no window and removes no desktop.

Each profile can leave some monitor configurations to macOS, such as the built-in display alone, and arrange the others, such as the built-in display with one external monitor.
While the active profile leaves the configuration of the monitors to macOS, the tool acts as while no profile is active.
The records of the profile stay as they are, a change of monitors leaves the windows where macOS puts them, and every desktop stays.
A switch to a profile that leaves the configuration to macOS makes the profile active and leaves every window where it is.
A switch to a profile that arranges the configuration restores its record of the configuration, or records the configuration as new when the profile has no record of it.
The application numbers and the search of the windows keep working in a configuration that the active profile leaves to macOS.
The window "Settings…" chooses, for each profile, the configurations that it arranges.

The user should be able to switch between level of definitions of "the same monitor configuration".
For instance, I like to have at least:

1. One mode, where "internal monitor only", "internal monitor + <x> external monitors", "<x> external monitors only" are different monitor configurations, but different external monitor types and names are not relevant.
2. Another mode, where every external monitor type and name is relevant, so "internal monitor + external monitor A" and "internal monitor + external monitor B" are different monitor configurations.

## Desktop operations that work around Hammerspoon on macOS 27.0.1

Hammerspoon 1.1.1 on macOS 27.0.1 reads the desktops and the windows on them, but fails to move a window to another desktop and to switch, add or remove desktops.
The issues https://github.com/Hammerspoon/hammerspoon/issues/3903 and https://github.com/Hammerspoon/hammerspoon/issues/3897 report the failures, read on 2026-10-10.

The tool shows a desktop by a press on its thumbnail in Mission Control, through the accessibility tree that macOS 27 keeps under the process `WindowManager`.
The tool waits for the desktop longer than the slowest press measured, and presses the thumbnail once more when the desktop is still inactive at a set time after the first press and Mission Control still shows.
When Mission Control has closed by that time and the desktop is still inactive, the tool opens Mission Control once more and presses the thumbnail again.
Before a press of the list or the search, the tool focuses the focused window of the application of the chosen window, or else its main window, when that window lies on the desktop that the press replaces.
The tool then waits a set time at most until the application is frontmost, and presses also when it is not.
The tool does so only while another application is frontmost.
Without that focus, macOS may show the replaced desktop again once the application becomes active after the press, as the README says.
After a press that Mission Control accepts, the tool closes Mission Control by a toggle only at the end of the wait, because a toggle may undo a press that is still taking effect.
The tool uses no keyboard shortcut to switch desktops.
macOS 27.0.1 unminimizes a window onto the desktop it was minimized on, also when another desktop shows, as the log of the tool showed on 2026-10-10.
The tool therefore restores a minimized window where it is.
A window on another desktop of its screen moves to its recorded desktop by its window id, through `hs.spaces.moveWindowToSpace` of the build of Hammerspoon with pull request #3889.
A window moves to another screen when the tool sets its frame there, and the tool sets a frame only while the window is on a desktop in view.
A window out of view that needs its frame, and a window that the tool cannot yet reach, come into view by a move by their window ids.
The tool moves windows without a switch of desktops.
It shows a desktop to bring back the desktop that each screen showed, to leave a window in full screen, and to reach a window from the list or the search.
Each move that fails shows in the alert after the switch.
While Mission Control shows for a press, the message on every screen asks the user to wait.
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
The default modifiers are Command-Option-Shift.

Every global shortcut of the tools can be changed, the shortcut of each action on its own.
One place registers the shortcuts of every tool, so that no tool keeps shortcut settings or binding code of its own.
A window of the menu bar item lists the actions with their keys, filters them, records a new shortcut, removes one and returns one to its default, and a file keeps the changes.
When a recorded shortcut belongs to another action or to macOS, the window says so and offers to take it from the other action or to turn the macOS shortcut off.

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
The default modifiers are Control-Option.
On 2026-10-10, the shortcuts of macOS and the menus of the running applications left Control-Option with a number unused.
Command with a number selects tabs, views and groups in many applications, and Command-Shift with 3, 4 and 5 takes screenshots in macOS.

## A shortcut searches every window by its title and its application

Control-Option-Command-Space shows a panel of its own, unlike the list of Control-Option, with the applications in a horizontal row and the previews of windows above it.
The user types to search the titles of the windows and the names of their applications by fuzzy matching.
The previews show the windows that match at any level, highlighted at levels that follow how well each one matches, and every window while nothing is typed.
Hovering over an application shows its windows, a click on an application chooses it and keeps its windows in view, and a click on a window brings it to the front with the focus.
Typing drops the application that the mouse chose, and shows the windows that match again.
The arrow keys move the selection among the previews in four directions, and Tab moves it in the order of the previews.
The user chooses the window to bring to the front, and a window on another desktop is reached by showing that desktop.
A URL `hammerspoon://desktop-manager?action=search-windows` shows the panel as well.
A window of the menu bar item picks the colors of the highlights of the selection, of the hover and of each level of match, with a preview and presets, and the next search uses them without a reload.

The tool keeps track of every window, also the minimized ones and the windows on desktops that the user has not visited since Hammerspoon started.
The search and the list of Control-Option show these windows, and the profiles record them.
Before a switch of profiles and before the restore after a change of monitors, the tool brings into view each window that it cannot yet reach and that the switch acts on.
The window moves by its id to the desktop in view of its screen.
The switch can then set the frame of the window or minimize it.

## Window tiling is a second tool beside the desktop manager

The window tiling sets the frame of the focused window to the whole screen or to one half of it, as Rectangle does.
Control-Option-Return fills the screen, and Control-Option with Left, Right, Up or Down takes the left, right, top or bottom half.
The tiling works without the Window menu of the application, because the shortcut Globe-Control-F of the item Window, Fill of macOS failed on a window just opened or focused, as the user found on 2026-10-11.
An Asyar extension of its own shows the item Fill Window, which opens a URL `hammerspoon://window-tiling?...` that the tool binds.
Asyar has its own window management for the halves, so the extension leaves them out, as the user decided on 2026-10-11.
A tiling started from Asyar acts on the window behind the search window of Asyar, and gives it the focus back.
The window tiling shares no module with the desktop manager, and has its own folders, settings, tests and Asyar extension.

## An Asyar extension opens and empties the Trash

An Asyar extension of its own shows the items Trash and Empty Trash.
Trash opens the Trash in the Finder.
Empty Trash shows the same confirmation as Finder, Empty Trash, and erases the items in the Trash only after the user confirms.

## Development practices that the project follows

The code is Lua 5.4, the version that Hammerspoon embeds.
The core that decides what to save and restore calls no Hammerspoon function, and unit tests run it with `lua` 5.4 outside Hammerspoon.
A separate module moves the windows and changes the desktops on macOS.
`luacheck` lints the code and `stylua` formats it, with their settings in the repository.
Changes are committed in small steps to the local repository, and nothing is pushed.
Hammerspoon loads the tool through a one-line `~/.hammerspoon/init.lua` that loads the `init.lua` of the repository.
The user runs the tests that move windows, on the user's own machine.
