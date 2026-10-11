# Save the desktops and windows of macOS as profiles, and switch between them with one key

This tool runs inside [Hammerspoon](https://www.hammerspoon.org) and adds two kinds of shortcuts to macOS.

- Command-Option-Shift with a number from 1 to 9 activates a profile.
  A profile records the desktops of each screen and the windows on each desktop, and activating it brings them back.
- Control-Option with a number shows a list of numbered applications and their windows, and brings the window you choose to the front.

For example, profile 1 holds a writing setup: an editor and a browser side by side on the built-in display, and Mail on a second desktop.
Profile 2 holds a teaching setup: slides on the external monitor and a terminal on the built-in display.
Command-Option-Shift-2 minimizes the editor, the browser and Mail, and brings back the slides and the terminal at the places that profile 2 recorded.
Command-Option-Shift-2 again deactivates profile 2, and macOS manages the windows as usual.

There's an Asyar extension to activate, deactivate profiles, and reset the application numbers.
Extra scripts are provided if you want to quickly call the actions from another launcher.

The tool runs on macOS 27.0.1 with Hammerspoon 1.1.1, the versions it was developed on.
`requirements.md` states what the tool must do.

## Install the tool in seven steps

1. Install Hammerspoon from its website, or with `brew install --cask hammerspoon`, and start it.
2. Clone this repository into a folder of your choice, and run `make install-loader` in that folder.
   The command writes `~/.hammerspoon/init.lua` with the one line `dofile("<folder>/init.lua")`.
   When `~/.hammerspoon/init.lua` exists already, the command leaves it unchanged, and you add the line to it yourself.
3. Click the hammer icon in the menu bar and choose Reload Config.
4. In System Settings, Privacy & Security, Accessibility, turn on Hammerspoon.
5. In System Settings, Keyboard, Keyboard Shortcuts, Mission Control, turn on "Switch to Desktop 1" and the next ones up to the number of desktops you use.
   The tool switches desktops with these shortcuts, Control-1 to Control-9.
6. In System Settings, Desktop & Dock, Mission Control, keep "Displays have separate Spaces" on, and turn "Automatically rearrange Spaces based on most recent use" off.
   The tool finds a desktop by its position, and a rearrangement moves the positions.
7. Shorten the animations, if you like.
   In System Settings, Desktop & Dock, set "Minimize windows using" to Scale Effect.
   In System Settings, Accessibility, Display, turn on "Reduce motion".

The menu bar then shows `◧`, and `◧ 2` while profile 2 is active.
The previews in the list of windows also need the permission for Screen Recording, as [the section on the limits of macOS](#hammerspoon-and-macos-2701-limit-what-the-tool-can-do) explains.

## Command-Option-Shift with a number activates, switches and deactivates profiles

| Keys | Effect |
|---|---|
| Command-Option-Shift-N, for N from 1 to 9 | activates profile N, or switches to it from the active profile |
| Command-Option-Shift-N while profile N is active | deactivates profile N |
| Command-Option-Shift-0 | deactivates the active profile |

A switch starts once you release the modifier keys, because the Control-number that the tool presses to switch desktops would otherwise combine with them.
While no profile is active, macOS manages the windows as usual.

A profile keeps one record per monitor configuration.
The record holds the number of desktops of each screen, the desktop in front, and every window that the tool sees while the profile is active.
Each window is recorded as in sight, on a desktop at its frame, or as out of sight.
A window is out of sight when it is minimized or its application is hidden.
The record names a window by its application, its window id and its title.
Windows do not belong to profiles, and two profiles may record the same window.

The tool updates the record of the active profile at four times:

- two seconds after a window opens, closes, moves, minimizes or changes its title;
- once a minute;
- at the end of a switch;
- before a switch to another profile.

When the monitors change to a configuration that the active profile recorded, the tool restores that record.
When the monitors change to a configuration that is new to the profile, macOS arranges the windows, and the profile starts recording the new configuration.
A choice in the menu bar item sets when two monitor configurations count as the same.

| Choice under "Same monitor configuration by" | Configurations that count as different |
|---|---|
| Number of external monitors, the default | the built-in display alone, the built-in display with one external monitor, two external monitors, and so on |
| Name of each external monitor | also the built-in display with `LG TV SSCR2` and the built-in display with `DELL U2720Q` |

The menu bar item also has entries that deactivate the active profile, rename it, update its record at once and print diagnostics.

## Control-Option with a number brings an application to the front

Each profile gives the numbers from 1 to 9 to applications.
While no profile is active, the numbers of profile 0 hold.
Profile 0 records no windows, so a switch minimizes no window on its account.

A press of Control-Option with a number shows a list of the numbered applications in the middle of the screen.
By default each application is a column, with its number, its icon and its name on top, and its windows stacked below, each a blurred preview with its title under it.

```text
┌──────────────────────────────────────────────────────────┐
│  1 ▣ Firefox         2 ▣ Code             3 ▣ Mail       │
│  ┌────────────┐      ┌────────────┐       ┌────────────┐ │
│  │  preview   │      │  preview   │       │  preview   │ │
│  └────────────┘      └────────────┘       └────────────┘ │
│  GitHub - pull       README.md —          Inbox          │
│  requests            desktop-manager                     │
│  ┌────────────┐                                          │
│  │  preview   │                                          │
│  └────────────┘                                          │
│  Hammerspoon docs                                        │
└──────────────────────────────────────────────────────────┘
```

- The press selects a window of the application of that number: the window that had the focus last, or the next window when the application is in front.
- Each further press of the same number, while you hold Control and Option, selects the next window of that application, in the order in which the windows opened.
- A press of another number selects a window of that application.
- Releasing Control or Option brings the selected window to the front.
- Escape closes the list without a switch.
- A press released at once brings the selected window to the front without showing the list.

The list holds every window of the application, also the windows that the active profile did not record, such as the minimized windows of another profile.
Bringing a window on another desktop to the front shows that desktop first.
An application without windows shows "no window, a new one opens", and gets a new window from the same sources that replace a closed window at a switch.

The tool gives the default numbers to the applications that the profile records in sight.
The order follows the screens, then the desktops, then the left edges of the windows, so the numbers read from left to right through the desktops.
A default number stays with its application while the profile records a window of it, in sight or out of sight.
Profile 0 numbers the applications with a window in sight in the same order, and a default number stays while its application has a window open.
Profile 0 updates its numbers when a profile would update its record, and at once when a profile is deactivated.

You can give a number to any running application under "Application numbers" in the menu bar item.
Each number there offers two choices: give the number to the application that was in front when the menu opened, or return the number to the default.
A number that you give stays until you change it.
Control-Option-0 returns every number of the active profile, or of profile 0, to the default, and an alert names the profile.
Control-Option-0 does nothing while the list shows, so a slip during a press keeps the numbers you gave.

Control-Option with a free number reaches the application in front unchanged.
A number given to an application takes Control-Option with that number from every other application.
On 2026-10-10, the shortcuts of macOS and the menus of the running applications left Control-Option with a number unused.
Command with a number would clash, because it selects tabs, views and groups in many applications, and Command-Shift with 3, 4 and 5 takes screenshots in macOS.

## Settings live in `desktop_manager/default_settings.lua`

To change a setting, edit the file and choose Reload Config.
The file writes each choice through its module, such as `list_layout.ROWS` for `rows`.

| Setting | Default | What it sets |
|---|---|---|
| `hotkey_modifiers` | Command-Option-Shift | the modifiers of the profile shortcuts |
| `app_hotkey_modifiers` | Control-Option | the modifiers of the application numbers |
| `profile_count` | 9 | the number of profiles |
| `app_number_count` | 9 | the number of application numbers |
| `concealment_method` | `minimize_windows` | how a window goes out of sight: `minimize_windows` minimizes it, and `hide_applications` hides its application once all the windows of the application go out of sight |
| `missing_window_policy` | `match_title_or_open_new_window` | what replaces a recorded window that no longer exists, as [the section on switches](#a-switch-changes-only-the-windows-that-differ-from-the-record) explains |
| `list_layout` | `columns` | how the list arranges the applications |
| `list_sizing` | `fill_screen` | how the list uses the screen |
| `preview_method` | `blurred_snapshots` | what the list shows beside a title: `blurred_snapshots` a blurred image of the window, or the icon for a window without an image, and `app_icons` the icon of the application |
| `preview_blur` | 1 | how blurred a preview is: 1 keeps full detail, 2 half of it, 4 a quarter |
| `preview_size` | 0.1 by 0.1 | the width and height of a preview, as fractions of the screen in front |
| `list_font_size` | 0.01 | the size of the titles, as a fraction of the height of the screen in front |
| `title_overflow` | `wrap` | what happens to a title longer than its space |
| `title_line_count` | 2 | the most lines of a title under `wrap` |
| `timing` | | the waits and time limits of a switch, in seconds |

Control alone does not work as `app_hotkey_modifiers`, because the tool presses Control with a number to switch desktops.

On a screen of 1440 by 875 points, a preview of 0.1 by 0.1 is 144 by 88 points, and a font size of 0.01 is about 9 points.
The names of applications are 2 points larger than the titles.
A preview keeps the proportions of its window.
The rows, the columns and the width of the list follow from the two sizes, so the list keeps its look on every display.

| Value of `list_layout` | The list |
|---|---|
| `columns` | a column per application, side by side |
| `columns_per_display` | the same columns in a group per display, from left to right as the displays stand, with the name of the display above its group |
| `rows` | a line per application, and under it a line per window with its preview beside the title |

Under `columns_per_display`, an application with windows on two displays has a column in each group.
A last unnamed group holds the windows on an unknown display and the applications without windows.

| Value of `list_sizing` | The list |
|---|---|
| `fill_screen` | grows or shrinks the previews and the fonts by one factor until the list fills 95 percent of the width or 90 percent of the height of the screen, up to 2.5 times the preview and 1.6 times the font of the settings |
| `fixed` | keeps the sizes of the settings, and shrinks them only when the list would not fit |

Under `fill_screen`, `preview_size` gives the shape of a preview and the size that the growth starts from.
Under both, the columns fold into two lines when two lines make the previews at least 5 percent larger.
The first line takes the larger half of the columns, so the numbers read from left to right and then downward.

| Value of `title_overflow` | A long title |
|---|---|
| `wrap` | flows over up to `title_line_count` lines, and its cell grows to them |
| `truncate` | is shortened to one line ending in an ellipsis |
| `scroll` | scrolls from right to left after a pause of one second while its window is selected, and is shortened otherwise |

## Asyar, Raycast and URLs reach the profiles from outside Hammerspoon

### The Asyar extension in `asyar-extension/` shows each profile as an item

The extension adds ten items to the search of [Asyar](https://asyar.org).

| Item | Enter |
|---|---|
| Profile 1 to Profile 9, with the name of a renamed profile after it, such as "Profile 2 · Writing" | activates the profile, or deactivates it while it is active |
| Reassign App Numbers | returns every number of the active profile, or of profile 0, to the default, as Control-Option-0 does |

The active profile shows a green dot, the label "Active profile" and the line "Active. Enter deactivates it.", and the other profiles show a white dot.
The extension reads `~/.hammerspoon/desktop-manager-state.json`, and draws the items again when the active profile or a name changes there.
The manifest, `asyar-extension/manifest.json`, limits the extension to three permissions and holds the path of the state file.

| Permission | Scope |
|---|---|
| `files:read` | `~/.hammerspoon/desktop-manager-state.json` alone |
| `fs:watch` | the same file |
| `shell:open-url` | the URLs that start with `hammerspoon://` |

Setting up the extension takes two steps, with Node and npm installed.

1. Run `npm install` in `asyar-extension/`.
2. Run `make link-asyar-extension` in the folder of this repository.
   The command builds the extension into `asyar-extension/dist/`, links the folder into `~/Library/Application Support/org.asyar.app/extensions/`, and registers it in `dev_extensions.json` there.

Quit Asyar and start it again, so that it loads the extension.

### The scripts in `launcher-scripts/` run in Asyar and Raycast

The scripts cover the actions that the extension lacks, such as renaming a profile or giving a number to an application, and they serve Raycast.
Each script opens one of the URLs below, and carries the headers of the Scripts feature of Asyar and of a Raycast script command.

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
A script title is fixed, so the titles name the profiles by number.

### A URL reaches every action

| Action | Shortcut or menu | URL `hammerspoon://desktop-manager?...` |
|---|---|---|
| Activate profile N, or switch to it | Command-Option-Shift-N | `action=activate&profile=N` |
| Deactivate profile N while it is active | Command-Option-Shift-N | `action=deactivate&profile=N` |
| Deactivate the active profile | Command-Option-Shift-0 | `action=deactivate` |
| Activate profile N, or deactivate it while it is active | Command-Option-Shift-N | `action=toggle&profile=N` |
| Rename profile N | menu, Rename active profile… | `action=rename&profile=N&name=Writing` |
| Change when monitor configurations are the same | menu, Same monitor configuration by | `action=cycle-monitor-matching` |
| Update the record of the active profile now | menu, Save arrangement now | `action=save` |
| Give number N to a running application | menu, Application numbers | `action=number-app&number=N&app=Firefox` |
| Return number N to the default | menu, Application numbers | `action=release-app-number&number=N` |
| Return every number to the default | Control-Option-0 | `action=reset-app-numbers` |

The numbers belong to the active profile, or to profile 0 while no profile is active.
In a terminal, `open -g "hammerspoon://desktop-manager?action=activate&profile=2"` activates profile 2.

## A switch changes only the windows that differ from the record

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

macOS gives a window that its application reopens a new window id, such as a window of Visual Studio Code after the application restarts.
When a recorded window in sight no longer exists, `missing_window_policy` chooses what replaces it.

| Value of `missing_window_policy` | The tool |
|---|---|
| `match_title_or_open_new_window`, the default | takes an open window of the same application with the same title, and opens a new window when no title matches |
| `open_new_window` | opens a new window of the same application |

Under the default, the tool also treats an unrecorded window as the reopened copy of a closed recorded window of the same application with the same title.
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

The tool saves the profiles, their records and their application numbers in `~/.hammerspoon/desktop-manager-state.json`.
A file that the tool cannot read is moved aside to a name that ends in `.unreadable-` and the time, and the tool starts a new state.

## Hammerspoon and macOS 27.0.1 limit what the tool can do

The functions of Hammerspoon 1.1.1 that move a window to another desktop, or that switch, add or remove desktops, fail on macOS 27.0.1.
The issues [#3903](https://github.com/Hammerspoon/hammerspoon/issues/3903) and [#3897](https://github.com/Hammerspoon/hammerspoon/issues/3897) of Hammerspoon report the failures.
The tool works around them as follows.

- macOS 27.0.1 unminimizes a window onto the desktop it was minimized on, also when another desktop shows, as the log of the tool showed on 2026-10-10.
  A switch therefore brings minimized windows back without switching desktops.
  For the same reason, a window on another desktop of its screen stays there, and the console notes it.
  A window moves to another screen when the tool sets its frame there.
- A desktop switch presses Control with the number of the desktop.
  Mission Control numbers the desktops of all screens in one sequence, so desktops after the ninth cannot be reached.
- Adding a desktop presses the add button of Mission Control through accessibility, under the process WindowManager, which worked on 2026-10-10.
  Mission Control opens for a moment during the addition.
  When the button is not found, the tool notifies you, and you add the desktop in Mission Control.
- Hammerspoon sees the windows of a desktop once you have visited it after Hammerspoon started.
  A switch leaves the windows of unvisited desktops as they are, and a record keeps their last known place.
- The window filter of Hammerspoon drops a window whose subrole changes while its application is hidden, as the window of Calendar does.
  The tool looks such windows up among all windows of macOS.

The previews in the list come after the list shows, one window at a time, and need the permission for Screen Recording.
Hammerspoon takes them with an old screen capture function of macOS.
On 2026-10-10, on macOS 27.0.1, that function blocked Hammerspoon for two minutes with every shortcut unresponsive, and took less than 0.3 seconds after the permission was turned on.
An image that takes longer than half a second therefore stops the previews until the next reload, and the console says why.
On a machine where Hammerspoon lacks the permission, choose `app_icons`, or time one image first.

1. In System Settings, Privacy & Security, Screen & System Audio Recording, turn on Hammerspoon.
2. In a terminal, run the command below, which may itself block Hammerspoon for minutes when the function blocks.

```sh
hs -c 'local started = hs.timer.secondsSinceEpoch(); local image = hs.window.snapshotForID(hs.window.focusedWindow():id()); return tostring(image ~= nil) .. " after " .. (hs.timer.secondsSinceEpoch() - started) .. " seconds"'
```

The previews work when the command prints `true` after less than half a second.

## Diagnostics in the Hammerspoon console show what the tool reads

`hs -c "desktop_manager:print_diagnostics()"` prints what the tool reads of the screens, desktops and windows, and which profiles recorded each window, and changes nothing.
"Print diagnostics to the console" in the menu bar item prints the same into the Hammerspoon console.
Each switch writes its plan and its duration to the console.
Each desktop switch also writes how long it waited for the release of the modifiers and how long macOS took to report the new desktop.
The rest of a switch is the animation of macOS, which "Reduce motion" in step 7 of the installation shortens.

## The code splits into a tested core and a macOS layer

| Folder or file | Content |
|---|---|
| `init.lua` | the file that Hammerspoon loads, which starts the controller |
| `desktop_manager/core/` | the decisions: monitor configurations, window matching, profile records, plans for concealing, restoring and opening missing windows, application numbers, URL commands |
| `desktop_manager/macos/` | the calls to Hammerspoon: reading screens, desktops and windows, switching desktops, opening new windows, switching to the application of a number, Mission Control, the menu bar item and the controller |
| `tests/` | unit tests of the core, and tests of whole switches against `tests/fake_hammerspoon.lua` |
| `tools/` | the generators of the launcher scripts and of the settings of the Asyar extension |
| `launcher-scripts/` | the scripts for Asyar and Raycast, written by the generator |
| `asyar-extension/` | the Asyar extension, in TypeScript, with its manifest, its worker and the unit tests of its items |

The modules of `desktop_manager/core/` call no Hammerspoon function, so `lua` 5.4 runs their tests outside Hammerspoon.
The fake of Hammerspoon unminimizes a window onto its own desktop, as macOS 27.0.1 does, and a test can make it unminimize onto the desktop that shows.
The tests check the logic of the tool, and say nothing about the behaviour of macOS.

`make check` checks the syntax with `luac -p`, lints with `luacheck`, checks the formatting with `stylua --check`, runs the tests, and compares the generated files with their generators.
`make format` formats the code with `stylua`.
The tools come from Homebrew: `lua@5.4`, `luacheck`, `stylua` and `lua-language-server`.

`make check-asyar-extension` checks the types of the extension, runs its unit tests, runs `asyar validate` of the SDK of Asyar, and builds it.
Run `make link-asyar-extension` again after a change to the extension, or `npm run build` in `asyar-extension/`, because Asyar loads the built files through the link.

Two generators take the numbers of profiles and of applications from `desktop_manager/default_settings.lua`.
`make launcher-scripts` runs `tools/write_launcher_scripts.lua`, which writes the scripts.
`make asyar-extension-settings` runs `tools/write_asyar_extension_settings.lua`, which writes `asyar-extension/src/settings.generated.json`.
Run them after a change of the settings, because `make check` fails when a generated file differs from the output of its generator.

The code follows the [LuaRocks style guide](https://github.com/luarocks/lua-style-guide), read on 2026-10-10, with four departures.

- Indentation is four spaces, as in the Lua extensions that Hammerspoon 1.1.1 ships, where the guide uses three.
- Types are written as annotations of lua-language-server, such as `---@param`, where the guide uses LDoc, because the language server checks them.
- Misuse of a function raises `error` with a message that states the fact and the value, where the guide uses `assert`.
- `init.lua` sets one global, `desktop_manager`, because Hammerspoon stops the hotkeys and watchers that Lua garbage-collects, and because the command-line tool `hs` reaches the controller through it.

Lines are at most 100 characters long, as `stylua.toml` and `.luacheckrc` set.
