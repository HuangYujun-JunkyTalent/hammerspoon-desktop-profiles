# The desktop manager switches between profiles of desktops and windows on macOS

The tool runs inside Hammerspoon and keeps nine numbered profiles.
A profile records how many desktops each screen has, which windows are on each desktop, and where each window sits.
Each profile also gives numbers to applications, and Control-Option with a number lists them and brings one to the front.
`requirements.md` states what the tool must do.

## A profile records its desktops and windows, and a switch changes only what differs

When no profile is active, macOS manages the windows as usual.

A profile holds one record per monitor configuration.
The record holds the number of desktops of each screen, the desktop in front, and every window that the tool sees while the profile is active.
The record names each window by its application, its window id and its title.
It keeps the window either as in sight, on a desktop with its frame, or as out of sight.
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

Activating a profile adds the desktops that the profile recorded and a screen lacks.
The tool removes no desktop, because removing a desktop moves the windows on it and changes what the other profiles recorded.
A switch shows another desktop for three reasons alone: to move a window to another screen, to open a new window on its recorded desktop, and to bring the desktop that the profile had in front back to the front.

## A window that no longer exists gets a new window of its application

macOS gives a window that its application reopens a new window id, such as a window of Visual Studio Code after the application restarts.
When a profile is activated and the window of a record in sight no longer exists, the setting `missing_window_policy` in `desktop_manager/default_settings.lua` chooses what happens.

| Value of `missing_window_policy` | The tool |
|---|---|
| `match_title_or_open_new_window`, the default | takes an open window of the same application with the same title, and opens a new window when no title matches |
| `open_new_window` | opens a new window of the same application |

Under the default, the tool also treats an unrecorded window as the reopened copy of a closed recorded window of the same application with the same title, before each update of a record and each switch.
Position and size play no part, because the tool sets them on the window it takes, and because macOS opens a new window at the place of the last closed one.
A reopened window whose title changed, such as a browser window on another tab, counts as a new window.

The new window comes from the first of three sources that gives one:

1. A window that a launch of the application opened during the same switch, when the application was not running.
2. The menu item "New Window" of the application, or "New Finder Window" of the Finder.
3. A reopen of the application, as a click on its icon in the Dock sends, which shows the main window of an application such as Calendar.

The tool leaves out Command-N, because Calendar, Mail, Notes and Slack create an event, a message or a note with it.
A window opens on the desktop that shows, so the tool shows the recorded desktop first, and then sets the recorded frame.
The records of every profile then name the new window.
An application that opens no new window within ten seconds is reported in a notification.
New windows open for records in sight alone.

The tool minimizes a window to take it out of sight.
The setting `concealment_method` in `desktop_manager/default_settings.lua` makes the tool hide an application instead, when all the windows of the application go out of sight.

When the monitors change to a configuration that the active profile recorded, the tool restores that record.
When the monitors change to a configuration that is new to the profile, macOS arranges the windows, and the profile starts recording the new configuration.

The menu bar item chooses when two monitor configurations are the same.

| Choice in the menu | Configurations that count as different |
|---|---|
| Number of external monitors | built-in display alone, built-in display with one external monitor, two external monitors, and so on |
| Name of each external monitor | also built-in display with `LG TV SSCR2` and built-in display with `DELL U2720Q` |

## Control-Option with a number lists the applications of the profile and brings one to the front

Each profile gives the numbers from 1 to 9 to applications.
A press of Control-Option with a number shows a list in the middle of the screen: the numbered applications of the active profile, with their numbers, their icons and the titles of their windows.
The setting `list_layout` in `desktop_manager/default_settings.lua` chooses how the list arranges them.

| Value of `list_layout` | The list |
|---|---|
| `columns`, the default | a column per application, side by side, with the number and the icon on top and the windows stacked downward, each a preview with its title under it |
| `columns_per_display` | the same columns in a group per display, from left to right as the displays stand, with the name of the display above its group, so an application with windows on two displays has a column in each group |
| `rows` | a line per application, and under it a line per window with its preview beside the title |

With `columns_per_display`, a last unnamed group holds the windows on an unknown display and the applications that have no window open.

- The press selects a window of the application of that number: the window that had the focus last, or the next window when the application is in front.
- Each further press of the same number, while you hold Control and Option, selects the next window of that application, in the order in which the windows opened.
- A press of another number selects a window of that application.
- Releasing Control or Option brings the selected window to the front.
  Escape closes the list without a switch.
- A press released at once brings the selected window to the front without showing the list.
- Each application line shows the icon of the application, and each window line shows the icon beside the title, or a blurred preview of the window under the setting below.
- The windows are all the windows of the application, also those that the active profile did not record, such as the minimized windows of another profile.
- A window on another desktop is reached by showing that desktop first.
- An application without windows shows "no window, a new one opens", and gets a new window from the same sources that replace a closed window at a switch.

The setting `preview_method` in `desktop_manager/default_settings.lua` chooses what a window line shows beside the title.

| Value of `preview_method` | A window line shows |
|---|---|
| `blurred_snapshots`, the default | a blurred image of the window, or the icon for a window without an image, such as a minimized one |
| `app_icons` | the icon of the application |

The setting `preview_blur` sets how blurred a preview is: 1 keeps full detail, the default, 2 half of it, and 4 a quarter.
A preview keeps the proportions of its window.
The sizes are fractions of the screen in front, so the list keeps its look on every display.
The setting `preview_size` sets the width and height of a preview as fractions of the width and height of the screen, 0.1 by 0.1 by default, which is 144 by 88 points on a screen of 1440 by 875 points.
The setting `list_font_size` sets the size of the titles as a fraction of the height of the screen, 0.016 by default, which is 14 points on that screen, and the names of applications are 2 points larger.
The rows, the columns and the width of the list follow from the two sizes.
The setting `list_sizing` chooses how the list uses the screen.

| Value of `list_sizing` | The list |
|---|---|
| `fill_screen`, the default | grows or shrinks the previews and the fonts by one factor until the list fills 95 percent of the width or 90 percent of the height of the screen, whichever it reaches first, up to 2.5 times the preview and 1.6 times the font of the settings |
| `fixed` | keeps the sizes of the settings, and shrinks them only when the list would not fit |

Under `fill_screen`, `preview_size` gives the shape of a preview and the size that the growth starts from.
In both, the columns fold into two lines when two lines make the previews at least 5 percent larger than one line does.
The first line takes the larger half of the columns, so the numbers read from left to right and then downward, and a display whose columns continue on the second line has its name above them there too.

The setting `title_overflow` chooses what happens to a title longer than its space.

| Value of `title_overflow` | A long title |
|---|---|
| `wrap`, the default | flows over the lines it needs, up to `title_line_count`, 2 by default, and its cell or line grows to them |
| `truncate` | is shortened to one line and ends in an ellipsis |
| `scroll` | scrolls from right to left after a pause of one second, when its window is selected, and is shortened otherwise |

The images come after the list shows, one window at a time, and need the permission for Screen Recording.
Hammerspoon takes them with an old screen capture function of macOS.
On 2026-10-10, on macOS 27.0.1, that function blocked Hammerspoon for two minutes with every shortcut unresponsive, and after the permission was turned on it took less than 0.3 seconds.
An image that takes longer than half a second therefore stops the images until the next reload, and the console says why.
On a machine where Hammerspoon lacks the permission, choose `app_icons`, or time one image first:

1. In System Settings, Privacy & Security, Screen & System Audio Recording, turn on Hammerspoon.
2. In a terminal, run the command below, which may itself block Hammerspoon for minutes when the function blocks.

```sh
hs -c 'local started = hs.timer.secondsSinceEpoch(); local image = hs.window.snapshotForID(hs.window.focusedWindow():id()); return tostring(image ~= nil) .. " after " .. (hs.timer.secondsSinceEpoch() - started) .. " seconds"'
```

The images work when the command prints `true` after less than half a second.

The tool gives the default numbers to the applications that the profile records in sight.
The order follows the screens, then the desktops, then the left edges of the windows, so the numbers read from left to right through the desktops.
A default number stays with its application while the profile records a window of it, in sight or out of sight, so the numbers stay put.
The menu bar item lists the numbers of the active profile under Application numbers.
Each number there has two choices: give the number to the application that was in front when the menu opened, or return the number to the default.
A number given by hand stays until you change it.

Control-Option with a free number, or with any number while no profile is active, reaches the application in front unchanged.
A number given to an application takes Control-Option with that number from every other application.
On 2026-10-10, the shortcuts of macOS and the menus of the running applications left Control-Option with a number unused.
Command with a number selects tabs, views and groups in many applications, and Command-Shift with 3, 4 and 5 takes screenshots in macOS.
The setting `app_hotkey_modifiers` in `desktop_manager/default_settings.lua` changes the modifiers.
Control alone does not work there, because the tool presses Control with a number to switch desktops.

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
| List the numbered applications and select application N, or its next window | Control-Option-N, for N from 1 to 9, and release to go there | none |
| Give number N to a running application in the active profile | menu bar item, Application numbers | `hammerspoon://desktop-manager?action=number-app&number=N&app=Firefox` |
| Return number N to the default in the active profile | menu bar item, Application numbers | `hammerspoon://desktop-manager?action=release-app-number&number=N` |

`open -g "hammerspoon://desktop-manager?action=activate&profile=2"` in a terminal activates profile 2.
A switch starts once the modifier keys are released, because the simulated Control-number would otherwise combine with them.
`desktop_manager/default_settings.lua` holds the modifiers of the profiles and of the application numbers, the number of profiles and of application numbers, the way of taking windows out of sight, what happens to a window that no longer exists, and the timings.

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
| Number App | the number and the name of a running application |
| Release App Number | the number |

In Asyar, add the folder `launcher-scripts/` in Settings, Scripts.
Asyar reads the folder without its subfolders, and shows a notification each time a script ends.
In Raycast, add the same folder in Settings, Script Commands, Add Script Directory.

A script title is fixed, so the titles name the profiles by number and not by name.
`tools/write_launcher_scripts.lua` writes the scripts, with the numbers of profiles and of applications taken from `desktop_manager/default_settings.lua`.
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

Each desktop switch writes to the console how long it waited for the release of the modifiers and how long macOS took to report the new desktop.
The rest of a switch is the animation of macOS, which "Reduce motion" in step 6 of the setup shortens.

`hs -c "desktop_manager:print_diagnostics()"` prints what the tool reads of the screens, desktops and windows, and which profiles recorded each window, and changes nothing.
The menu bar item, Print diagnostics to the console, prints the same into the Hammerspoon console.
Each switch writes its plan and its duration to the Hammerspoon console.

## The code splits into a tested core and a macOS layer

| Folder or file | Content |
|---|---|
| `init.lua` | the file that Hammerspoon loads, which starts the controller |
| `desktop_manager/core/` | the decisions: monitor configurations, window matching, profile records, plans for concealing, restoring and opening missing windows, application numbers, URL commands |
| `desktop_manager/macos/` | the calls to Hammerspoon: reading screens, desktops and windows, switching desktops, opening new windows, switching to the application of a number, Mission Control, the menu bar item and the controller |
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

The tool saves the profiles, their records and their application numbers in `~/.hammerspoon/desktop-manager-state.json`.
A file that the tool cannot read is moved aside to a name that ends in `.unreadable-` and the time, and the tool starts a new state.
