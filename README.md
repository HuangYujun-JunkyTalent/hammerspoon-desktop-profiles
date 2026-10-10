# The desktop manager switches between profiles of desktops and windows on macOS

The tool runs inside Hammerspoon and keeps nine numbered profiles.
A profile remembers how many desktops each screen has, which windows are open on each desktop, and where each window sits.
`requirements.md` states what the tool must do.

## A profile owns its windows and remembers them per monitor configuration

When no profile is active, macOS manages the windows as usual.
Activating a profile takes the windows of the other profiles out of sight.
An application whose windows all belong to other profiles is hidden, and in any other application those windows are minimized.
The profile then gets back its desktops and its windows, at the desktops and frames it last saved.
A saved window whose application is not running makes the tool launch the application and place the new window.
A window opened while a profile is active joins that profile.
Windows that belong to no profile join the profile that is activated next.

While a profile is active, the tool saves its arrangement two seconds after a window moves, opens or closes, and once a minute.
The tool keeps one arrangement per monitor configuration.
When the monitors change to a configuration that the profile remembers, the tool restores that arrangement.
When the monitors change to a configuration that is new to the profile, macOS arranges the windows, and the tool starts remembering the new configuration.

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
6. Optional: in System Settings, Accessibility, Display, turn on "Reduce motion", which shortens the animations of desktop switches and of Mission Control.

The menu bar shows `◧` after the reload, and `◧ 2` while profile 2 is active.

## Shortcuts, the menu bar item and URLs control the profiles

| Action | Shortcut | URL |
|---|---|---|
| Activate profile N, or switch to it | Command-Option-Shift-N, for N from 1 to 9 | `hammerspoon://desktop-manager?action=activate&profile=N` |
| Deactivate the active profile N | Command-Option-Shift-N again | `hammerspoon://desktop-manager?action=toggle&profile=N` |
| Deactivate any profile | Command-Option-Shift-0 | `hammerspoon://desktop-manager?action=deactivate` |
| Rename profile N | menu bar item, Rename active profile | `hammerspoon://desktop-manager?action=rename&profile=N&name=Writing` |
| Change when monitor configurations are the same | menu bar item, Same monitor configuration by | `hammerspoon://desktop-manager?action=cycle-monitor-matching` |
| Save the arrangement now | menu bar item, Save arrangement now | `hammerspoon://desktop-manager?action=save` |

`open -g "hammerspoon://desktop-manager?action=activate&profile=2"` in a terminal activates profile 2.
A switch starts once the modifier keys are released, because the simulated Control-number would otherwise combine with them.
`default_settings.lua` holds the modifiers, the number of profiles and the timings.

## Asyar and Raycast run the scripts in `launcher-scripts/`

Each script carries the headers that the Scripts extension of Asyar reads and the headers of a Raycast script command.

| Script | Arguments |
|---|---|
| `switch-desktop-profile.sh` | the profile number |
| `deactivate-desktop-profile.sh` | none |
| `rename-desktop-profile.sh` | the profile number and the new name |
| `cycle-monitor-matching.sh` | none |

In Asyar, add the folder `launcher-scripts/` in Settings, Scripts.
In Raycast, add the same folder in Settings, Script Commands, Add Script Directory.

## The first version has known limits on macOS 27.0.1

Hammerspoon 1.1.1 on macOS 27.0.1 cannot move a window to another desktop and cannot switch, add or remove desktops.
The issues https://github.com/Hammerspoon/hammerspoon/issues/3903 and https://github.com/Hammerspoon/hammerspoon/issues/3897 report the failures.
The tool works around them in three ways, and none of them has run on macOS 27.0.1 yet.

- A window moves to another desktop by being minimized and then unminimized while the target desktop shows.
  The move works only if macOS unminimizes a window onto the desktop that shows.
  The tool checks the desktop of each window afterwards and notifies you of each window that stayed.
- A desktop switch presses Control-N.
  Mission Control numbers the desktops of all screens in one sequence, so desktops after the ninth cannot be reached.
- Adding and removing desktops presses the buttons of Mission Control through accessibility, under the process WindowManager.
  When the buttons are not found, the tool notifies you, and you add or remove the desktops in Mission Control.

Hammerspoon sees the windows of a desktop once you have visited it after Hammerspoon started.
A switch therefore adopts and minimizes the windows of the visited desktops alone.

`hs -c "desktop_manager:print_diagnostics()"` prints what the tool reads of the screens, desktops and windows, and changes nothing.
The menu bar item, Print diagnostics to the console, prints the same into the Hammerspoon console.

## The code splits into a tested core and a macOS layer

| Folder or file | Content |
|---|---|
| `init.lua` | the file that Hammerspoon loads, which starts the controller |
| `desktop_manager/core/` | the decisions: monitor configurations, window matching, profile state, plans for concealing and restoring, URL commands |
| `desktop_manager/macos/` | the calls to Hammerspoon: reading screens, desktops and windows, switching desktops, Mission Control, the menu bar item and the controller |
| `tests/` | unit tests of the core, and tests of whole switches against `tests/fake_hammerspoon.lua` |
| `launcher-scripts/` | the scripts for Asyar and Raycast |

The modules of `desktop_manager/core/` call no Hammerspoon function, so `lua` 5.4 runs their tests outside Hammerspoon.
The fake of Hammerspoon assumes that macOS unminimizes a window onto the desktop that shows.
The tests therefore check the logic of the tool, and say nothing about the behaviour of macOS.

`make check` checks the syntax with `luac -p`, lints with `luacheck`, checks the formatting with `stylua --check`, and runs the tests.
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

The tool saves the profiles, their windows and their arrangements in `~/.hammerspoon/desktop-manager-state.json`.
A file that the tool cannot read is moved aside to a name that ends in `.unreadable-` and the time, and the tool starts a new state.
