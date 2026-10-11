# The desktop manager switches between profiles of desktops and windows on macOS

The tool runs inside Hammerspoon and keeps nine numbered profiles.
A profile records how many desktops each screen has, which windows are on each desktop, and where each window sits.
`requirements.md` states what the tool must do.

## A profile records its desktops and windows, and a switch changes only what differs

When no profile is active, macOS manages the windows as usual.

A profile holds one record per monitor configuration.
The record holds the number of desktops of each screen, the desktop in front, and every window that the tool sees while the profile is active.
The record keeps a window either as in sight, on a desktop with its frame, or as out of sight.
A window is out of sight when it is minimized or its application is hidden.
Windows do not belong to profiles, and two profiles may record the same window.

The tool updates the record of the active profile two seconds after a window opens, closes, moves, minimizes or changes its title.
It also updates the record once a minute, at the end of a switch, and before a switch to another profile.

Activating a profile does the least work that brings back what the profile recorded.

| The open window | The tool |
|---|---|
| is where the profile recorded it, at the same frame | does nothing |
| is on its recorded desktop at another frame | sets the recorded frame |
| is minimized, and the profile recorded it in sight | unminimizes it where it is |
| is in sight on another desktop of its recorded screen | leaves it there, because macOS 27.0.1 gives no way to move it, and notes it in the console |
| is on another screen than the recorded one | shows the recorded desktop on that screen when another desktop shows, and moves the window there |
| is in sight, and the profile recorded it out of sight | minimizes it |
| is in sight, and another profile recorded it while this profile did not | minimizes it |
| was recorded by no profile, such as a window opened while no profile was active | leaves it, and the profile records it at its next update |

A recorded window whose application is not running makes the tool launch the application and place the new window.
A recorded window that was closed while its application kept running is skipped.

Activating a profile adds the desktops that the profile recorded and a screen lacks.
The tool removes no desktop, because removing a desktop moves the windows on it and changes what the other profiles recorded.
A switch shows another desktop only to move a window to another screen, and to bring the desktop that the profile had in front back to the front.

macOS gives a window that its application reopens a new window id, such as a window of Visual Studio Code after the application restarts.
Before each update of a record and each switch, the tool treats an unrecorded window as the reopened copy of a closed recorded window, when both belong to the same application and have the same document or the same title.
The records of every profile then name the new window.
The place of the window plays no part, because macOS opens a new window at the place of the last closed one.
A reopened window whose title changed, such as a browser window on another tab, stays a new window, and the active profile records it at its next update.

The tool minimizes a window to take it out of sight.
The setting `concealment_method` in `desktop_manager/default_settings.lua` makes the tool hide an application instead, when all the windows of the application go out of sight.

When the monitors change to a configuration that the active profile recorded, the tool restores that record.
When the monitors change to a configuration that is new to the profile, macOS arranges the windows, and the profile starts recording the new configuration.

The menu bar item chooses when two monitor configurations are the same.

| Choice in the menu | Configurations that count as different |
|---|---|
| Number of external monitors | built-in display alone, built-in display with one external monitor, two external monitors, and so on |
| Name of each external monitor | also built-in display with `LG TV SSCR2` and built-in display with `DELL U2720Q` |

## Setting up the tool takes six steps

1. Run `make install-loader` in this folder.
   The command writes `~/.hammerspoon/init.lua` with one line that loads `init.lua` of this folder, and leaves an existing file unchanged.
2. Click the hammer icon in the menu bar and choose Reload Config.
3. In System Settings, Privacy & Security, Accessibility, turn on Hammerspoon.
4. In System Settings, Keyboard, Keyboard Shortcuts, Mission Control, turn on "Switch to Desktop 1" and the next ones up to the number of desktops you use.
   The tool switches desktops with these shortcuts, Control-1 to Control-9.
5. In System Settings, Desktop & Dock, Mission Control, keep "Displays have separate Spaces" on and "Automatically rearrange Spaces based on most recent use" off.
   The tool finds a desktop by its position, and a rearrangement moves the positions.
6. Optional: shorten the animations.
   In System Settings, Desktop & Dock, set "Minimize windows using" to Scale Effect.
   In System Settings, Accessibility, Display, turn on "Reduce motion".

The menu bar shows `◧` after the reload, and `◧ 2` while profile 2 is active.

## Shortcuts, the menu bar item, URLs and launcher scripts control the profiles

| Action | Shortcut | URL |
|---|---|---|
| Activate profile N, or switch to it | Command-Option-Shift-N, for N from 1 to 9 | `hammerspoon://desktop-manager?action=activate&profile=N` |
| Deactivate profile N while it is active | Command-Option-Shift-N again | `hammerspoon://desktop-manager?action=deactivate&profile=N` |
| Deactivate the active profile | Command-Option-Shift-0 | `hammerspoon://desktop-manager?action=deactivate` |
| Activate profile N, or deactivate it while it is active | Command-Option-Shift-N | `hammerspoon://desktop-manager?action=toggle&profile=N` |
| Rename profile N | menu bar item, Rename active profile… | `hammerspoon://desktop-manager?action=rename&profile=N&name=Writing` |
| Change when monitor configurations are the same | menu bar item, Same monitor configuration by | `hammerspoon://desktop-manager?action=cycle-monitor-matching` |
| Update the record of the active profile now | menu bar item, Save arrangement now | `hammerspoon://desktop-manager?action=save` |

`open -g "hammerspoon://desktop-manager?action=activate&profile=2"` in a terminal activates profile 2.
A switch starts once the modifier keys are released, because the simulated Control-number would otherwise combine with them.
`desktop_manager/default_settings.lua` holds the modifiers, the number of profiles, the way of taking windows out of sight and the timings.

## Asyar and Raycast run the scripts in `launcher-scripts/`

Each script opens one of the URLs above, and carries the headers of the Scripts feature of Asyar and of a Raycast script command.

| Script title | Arguments |
|---|---|
| Activate Profile 1 to Activate Profile 9 | none |
| Deactivate Profile 1 to Deactivate Profile 9 | none |
| Deactivate Active Profile | none |
| Rename Profile | the profile number and the new name |
| Cycle Profile Monitor Matching | none |
| Save Profile Arrangement | none |

In Asyar, add the folder `launcher-scripts/` in Settings, Scripts.
Asyar reads the folder without its subfolders, and shows a notification each time a script ends.
In Raycast, add the same folder in Settings, Script Commands, Add Script Directory.

A script title is fixed, so the titles name the profiles by number and not by name.
`tools/write_launcher_scripts.lua` writes the scripts, with the number of profiles taken from `desktop_manager/default_settings.lua`.
`make launcher-scripts` writes them again after a change of the generator, and `make check` fails when the folder differs from the output of the generator.

## The tool works around the limits of Hammerspoon and macOS 27.0.1

The functions of Hammerspoon 1.1.1 that move a window to another desktop, or that switch, add or remove desktops, fail on macOS 27.0.1.
The issues https://github.com/Hammerspoon/hammerspoon/issues/3903 and https://github.com/Hammerspoon/hammerspoon/issues/3897 report the failures.

- macOS 27.0.1 unminimizes a window onto the desktop it was minimized on, also when another desktop shows, as the log of the tool showed on 2026-10-10.
  A switch therefore brings minimized windows back without switching desktops.
  For the same reason, a window on another desktop of its screen stays there, and the console notes it.
  A window moves to another screen when the tool sets its frame there.
- A desktop switch presses Control-N.
  Mission Control numbers the desktops of all screens in one sequence, so desktops after the ninth cannot be reached.
- Adding a desktop presses the add button of Mission Control through accessibility, under the process WindowManager, which worked on 2026-10-10.
  Mission Control opens for a moment during the addition.
  When the button is not found, the tool notifies you, and you add the desktop in Mission Control.
- Hammerspoon sees the windows of a desktop once you have visited it after Hammerspoon started.
  A switch leaves the windows of unvisited desktops as they are, and a record keeps their last known place.
- The window filter of Hammerspoon drops a window whose subrole changes while its application is hidden, as the window of Calendar does.
  The tool looks such windows up among all windows of macOS.

`hs -c "desktop_manager:print_diagnostics()"` prints what the tool reads of the screens, desktops and windows, and which profiles recorded each window, and changes nothing.
The menu bar item, Print diagnostics to the console, prints the same into the Hammerspoon console.
Each switch writes its plan and its duration to the Hammerspoon console.

## The code splits into a tested core and a macOS layer

| Folder or file | Content |
|---|---|
| `init.lua` | the file that Hammerspoon loads, which starts the controller |
| `desktop_manager/core/` | the decisions: monitor configurations, window matching, profile records, plans for concealing and restoring, URL commands |
| `desktop_manager/macos/` | the calls to Hammerspoon: reading screens, desktops and windows, switching desktops, Mission Control, the menu bar item and the controller |
| `tests/` | unit tests of the core, and tests of whole switches against `tests/fake_hammerspoon.lua` |
| `tools/` | the generator of the launcher scripts |
| `launcher-scripts/` | the scripts for Asyar and Raycast, written by the generator |

The modules of `desktop_manager/core/` call no Hammerspoon function, so `lua` 5.4 runs their tests outside Hammerspoon.
The fake of Hammerspoon unminimizes a window onto its own desktop, as macOS 27.0.1 does, and a test can make it unminimize onto the desktop that shows.
The tests check the logic of the tool, and say nothing about the behaviour of macOS.

`make check` checks the syntax with `luac -p`, lints with `luacheck`, checks the formatting with `stylua --check`, runs the tests and compares the launcher scripts with the generator.
`make format` formats the code with `stylua`.
The tools come from Homebrew: `lua@5.4`, `luacheck`, `stylua` and `lua-language-server`.

## The code follows the LuaRocks style guide with four departures

The code follows the LuaRocks style guide at https://github.com/luarocks/lua-style-guide, read on 2026-10-10, because Google publishes no style guide for Lua.
The code departs from it in four places.

- Indentation is four spaces, as in the Lua extensions that Hammerspoon 1.1.1 ships, where the guide uses three.
- Types are written as annotations of lua-language-server, such as `---@param`, where the guide uses LDoc, because the language server checks them.
- Misuse of a function raises `error` with a message that states the fact and the value, where the guide uses `assert`.
- `init.lua` sets one global, `desktop_manager`, because Hammerspoon stops the hotkeys and watchers that Lua garbage-collects, and because the command-line tool `hs` reaches the controller through it.

Lines are at most 100 characters long, as `stylua.toml` and `.luacheckrc` set.

## The state lives in one JSON file

The tool saves the profiles and their records in `~/.hammerspoon/desktop-manager-state.json`.
A file that the tool cannot read is moved aside to a name that ends in `.unreadable-` and the time, and the tool starts a new state.
