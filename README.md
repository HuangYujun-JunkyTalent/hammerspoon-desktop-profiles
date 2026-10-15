# Save the desktops and windows of macOS as profiles, bring applications to the front by number, and tile windows

This repository holds two tools that run inside [Hammerspoon](https://www.hammerspoon.org).

The desktop manager adds three kinds of shortcuts to macOS.

- Command-Option-Shift with a number from 1 to 9 activates a profile.
  A profile records the desktops of each screen and the windows on each desktop, and activating it brings them back.
- Control-Option with a number shows a list of numbered applications and their windows, and brings the window you choose to the front.
- Control-Option-Command-Space shows every window above a row of the applications, and brings the window that you type or click to the front.

For example, profile 1 holds a writing setup: an editor and a browser side by side on the built-in display, and Mail on a second desktop.
Profile 2 holds a teaching setup: slides on the external monitor and a terminal on the built-in display.
Command-Option-Shift-2 minimizes the editor, the browser and Mail, and brings back the slides and the terminal at the places that profile 2 recorded.
Command-Option-Shift-2 again deactivates profile 2, and macOS manages the windows as usual.

The window tiling puts the focused window on the whole screen or on one half of it, with Control-Option and Return or an arrow, as [Rectangle](https://rectangleapp.com) does.

Each tool has an extension for the launcher [Asyar](https://asyar.org).
A third Asyar extension, in `asyar-trash/`, opens the Trash and empties it after a confirmation.
The scripts in `launcher-scripts/` run the actions of the desktop manager from Asyar or Raycast.

The tools run on macOS 27.0.1 with Hammerspoon 1.1.1, the versions they were developed on.
`requirements.md` states what the tools must do.

## Install the tools in seven steps

1. Install Hammerspoon from its website, or with `brew install --cask hammerspoon`, and start it.
2. Clone this repository into a folder of your choice, and run `make install-loader` in that folder.
   The command writes `~/.hammerspoon/init.lua` with the one line `dofile("<folder>/init.lua")`.
   When `~/.hammerspoon/init.lua` exists already, the command leaves it unchanged, and you add the line to it yourself.
3. Click the hammer icon in the menu bar and choose Reload Config.
4. In System Settings, Privacy & Security, Accessibility, turn on Hammerspoon.
5. In the folder of the repository, run `make enable-desktop-shortcuts`, which turns on the macOS shortcuts "Switch to Desktop 1" to "Switch to Desktop 10" as Control-Option-Shift-Command with 1 to 9 and 0, and keeps your other shortcuts.
   The desktop manager also runs the same script by itself when a switch needs a shortcut that is off, so the step only saves the wait of that first switch.
   You can also turn them on in System Settings, Keyboard, Keyboard Shortcuts, Mission Control, but that list shows the shortcut of a desktop only while the desktop exists.
   The desktops of all screens count in one sequence, so an external monitor adds desktops whose shortcuts the list did not show before.
   To see more shortcuts there, add desktops in Mission Control first.
   The desktop manager switches desktops with these shortcuts, Control-Option-Shift-Command with the number of the desktop and with 0 for the tenth desktop.
   Four modifiers leave the shortcuts to no other application, while Control with a number alone is free for the applications that use it.
6. In System Settings, Desktop & Dock, Mission Control, keep "Displays have separate Spaces" on, and turn "Automatically rearrange Spaces based on most recent use" off.
   The desktop manager finds a desktop by its position, and a rearrangement moves the positions.
7. Shorten the animations, if you like.
   In System Settings, Desktop & Dock, set "Minimize windows using" to Scale Effect.
   In System Settings, Accessibility, Display, turn on "Reduce motion".

The menu bar then shows `◧`, and `◧ 2` while profile 2 is active.
The previews in the list of windows also need the permission for Screen Recording, as [the section on the limits of macOS](#hammerspoon-and-macos-2701-limit-what-the-desktop-manager-can-do) explains.

## Command-Option-Shift with a number activates, switches and deactivates profiles

| Keys | Effect |
|---|---|
| Command-Option-Shift-N, for N from 1 to 9 | activates profile N, or switches to it from the active profile |
| Command-Option-Shift-N while profile N is active | deactivates profile N |
| Command-Option-Shift-0 | deactivates the active profile |

A switch starts once you release the modifier keys, because the Control-number that the desktop manager presses to switch desktops would otherwise combine with them.
While a switch moves windows, a message at the top of every screen reads "Arranging Profile 2… please wait", and it disappears when the switch ends.
Leave the windows and the desktops alone until then, because the desktop manager may move a window again after you have moved it, or open a window on the desktop that you switched to.
While no profile is active, macOS manages the windows as usual.

A profile keeps one record per monitor configuration.
The record holds the number of desktops of each screen, the desktop in front, and every window of a managed application while the profile is active, on every desktop.
A window on a desktop that has not shown since Hammerspoon started is recorded from the list of all windows of macOS, with its desktop, its frame and its title.
Each window is recorded as in sight, on a desktop at its frame, or as out of sight.
A window is out of sight when it is minimized or its application is hidden.
The record names a window by its application, its window id and its title.
Windows do not belong to profiles, and two profiles may record the same window.

The desktop manager updates the record of the active profile at four times:

- two seconds after a window opens, closes, moves, minimizes or changes its title;
- once a minute;
- at the end of a switch;
- before a switch to another profile.

When the monitors change, the desktop manager waits for macOS to move the windows, for `screen_settle_seconds` of `timing`, 3 seconds by default, and the message at the top of every screen says so.
When the new configuration is one that the active profile recorded, the desktop manager then restores that record, and the message stays until the restore ends.
When the new configuration is new to the profile, an alert says that the windows stay where macOS put them, and the profile starts recording the new configuration.
In both cases the desktop manager then removes the empty desktops that macOS left, as the next section says.
A choice in the menu bar item sets when two monitor configurations count as the same.

| Choice under "Same monitor configuration by" | Configurations that count as different |
|---|---|
| Number of external monitors, the default | the built-in display alone, the built-in display with one external monitor, two external monitors, and so on |
| Name of each external monitor | also the built-in display with `LG TV SSCR2` and the built-in display with `DELL U2720Q` |

The menu bar item also has entries that deactivate the active profile, rename it, update its record at once and print diagnostics.

### The desktop manager keeps the number of desktops of each display, and removes the empty desktops that macOS leaves

When a monitor disconnects, macOS removes the first desktop of the monitor and moves its other desktops, with their windows, to the end of the built-in display.
When the monitor returns, macOS gives it back one desktop, and the others stay on the built-in display.
The desktop manager keeps the number of desktops of each display, so that such desktops do not pile up on the built-in display.

The number of a display follows the desktops that you add or remove in Mission Control while the monitors stay connected.
The desktops that macOS moves at a change of monitors leave the number as it was.
A display starts with the desktops it has when the desktop manager first sees it.
The display goes by its name in the monitor configuration, such as `built-in` or `external 1`, so two monitors that count as the same configuration share a number.
"Print diagnostics" in the menu bar item shows the numbers.

After a change of monitors, and after the restore of the active profile, the desktop manager removes each desktop beyond the number of its display that is out of view and empty.
The removal starts from the end of the display, where macOS puts the desktops it moves, and the desktops up to the number stay, also when they are empty.
A window counts when the list of all windows of macOS places it on that desktop alone, or when Hammerspoon knows it and places it there, as for a minimized window.
A window that macOS shows on every desktop counts for none of them.
The removal opens Mission Control for a moment, and the message at the top of every screen reads "Removing 2 empty desktops from built-in… please wait".
A desktop beyond the number that holds a window stays, and the console of Hammerspoon notes it.
Such a desktop goes at a later change of monitors once it is empty, or when you remove it in Mission Control.
The restore after a change of monitors adds desktops to a display up to its number at most, because the removal would take away a desktop beyond it.

For example, the built-in display has 3 desktops and a Dell monitor has 4.
When the Dell monitor disconnects, the built-in display has 6 desktops, and the desktop manager removes those of the 3 moved desktops that hold no window.
When the Dell monitor returns with one desktop, the restore of the active profile adds 3 desktops to it and moves the windows of the profile back to them.
The desktop manager then removes the desktops left empty on the built-in display, which has 3 desktops again when the profile held every window of the moved desktops.
A window of an application that the desktop manager leaves to macOS stays on its moved desktop, and that desktop stays too.
Before the restore, the desktop manager shows each moved desktop that holds a window Hammerspoon has not seen, so such a window moves to the monitor as well.

### "Clear profile" in the menu bar item empties a profile

"Clear profile" lists every profile, and a profile without a saved layout shows dimmed.
After you confirm, the profile forgets the desktops and windows it saved for every monitor configuration, and keeps its name and its application numbers.
A cleared profile acts as a new one: activating it minimizes the windows that other profiles recorded, and brings back nothing.
A cleared active profile stays active and records the windows from its next update on.

### "Managed applications…" in the menu bar item leaves some applications to macOS

"Managed applications…" opens a window with two modes and a list of applications to tick.

| Mode | The desktop manager manages |
|---|---|
| Manage every application except the ticked ones, the default | every application while nothing is ticked, and otherwise the applications left unticked |
| Manage only the ticked applications | the ticked applications alone, and no window while nothing is ticked |

Each tick and each change of the mode applies at once, and the window stays open until you press Done, Escape or its close button.
Each mode keeps its own ticks, so changing the mode back brings back the earlier ticks.
The list shows the applications with a window open and the ticked ones, and the choice holds for every profile.
The desktop manager never minimizes, moves, opens or records a window of an application that it does not manage, and macOS keeps managing those windows.
A profile forgets the windows of such an application at its next update, so the application gets no default number, and you can still give it a number by hand.
A state saved before the modes existed keeps its list of managed applications, as the ticks of "Manage only the ticked applications".

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
The list also holds the windows on the desktops that you have not visited since Hammerspoon started.
Bringing a window on another desktop to the front shows that desktop first.
An application without windows shows "no window, a new one opens", and gets a new window from the same sources that replace a closed window at a switch.

The desktop manager gives the default numbers to the applications that the profile records in sight.
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

## Control-Option-Command-Space searches every window by its title and its application

Control-Option-Command-Space shows a panel in the middle of the screen, with a line for the search on top, the previews of windows in the middle, and the applications with a window in a row at the bottom.

```text
┌──────────────────────────────────────────────────────────────┐
│ gh pull▏                                2 of 9 windows match │
│                                                              │
│   ┌──────────────┐   ┌──────────────┐                        │
│   │   preview    │   │   preview    │                        │
│   └──────────────┘   └──────────────┘                        │
│   GitHub - pull…     Pull request #4…                        │
│   Firefox            Safari                                  │
│                                                              │
│    1 ▣      2 ▣       ▣        ▣                             │
│   Firefox   Code    Safari   Finder                          │
└──────────────────────────────────────────────────────────────┘
```

The previews show the windows of the application that you chose with a click, else of the application under the mouse, else the windows that match what you typed.
While you have typed nothing, every window shows.
The applications stand in the order in which their windows last had the focus, and the numbered ones carry their numbers.

| Action | Effect |
|---|---|
| typing | shows the windows that match, the best match first and selected, and drops the application that the mouse chose |
| Left, Right, Up or Down | selects the window beside, above or below the selected one in the grid of the previews, stops at its edges, and selects the last preview of a shorter last row below |
| Tab or Shift-Tab | selects the next or the previous window in the order of the previews, and goes round at the ends |
| Return | brings the selected window to the front, and shows its desktop first when another desktop shows |
| Delete, Command-Delete or Option-Delete | removes the last letter, or clears the search |
| hovering over an application | shows its windows, until the mouse moves onto another application or out of the panel |
| clicking an application | keeps its windows in view while the mouse moves on, and a second click releases it |
| hovering over a window | selects it |
| clicking a window | brings it to the front |
| Escape, or Control-Option-Command-Space again | closes the panel |

Before you type, the window that had the focus before the focused one is selected, so Return goes back to it.

Each word of the search must appear in the title or in the name of the application, with its letters in order, in capitals or not.
For example, `gh pull` finds the window "GitHub - pull requests" of Firefox, and `fx` finds every window of Firefox.
A letter of the search counts 2 when the letter before it in the search stands right before it in the text, or when it starts a word of the text, and 1 elsewhere.
A capital after a small letter starts a word, as the `H` of `GitHub` does.
The match of a word is the sum of its letters divided by twice the number of its letters, from 0.5 to 1, and the match of a search of several words is the mean of their matches.
Each window that matches gets a highlight of its level, and each application gets the highlight of its best window, while the applications without a match fade.

| Highlight | Match | Examples in "Firefox" |
|---|---|---|
| strong | 0.9 or more | `fire` matches 1 |
| medium | from 0.7 to below 0.9 | `fox` matches 5/6, and `fx` matches 3/4 |
| weak | below 0.7 | `frx` matches 4/6 |

The settings `list_font_size`, `preview_size` and `preview_method` shape the panel as well, and `preview_size` gives the shape of the previews.
While the panel shows, every key goes to the search, and the application in front receives none.
The search reads the keys themselves, so an input method such as Pinyin composes no characters there.

The panel also holds the windows on desktops that you have not visited since Hammerspoon started, as [the section on the limits of macOS](#hammerspoon-and-macos-2701-limit-what-the-desktop-manager-can-do) explains.
On 2026-10-12, the shortcuts of macOS used Space with Control and with Control-Option alone, and Asyar used Command-Space, so Control-Option-Command-Space was free.

## "Keyboard shortcuts…" in the menu bar item changes the shortcut of every action

Every global shortcut of the desktop manager and of the window tiling is in one list, which one module binds, `keyboard_shortcuts/macos/shortcut_center.lua`.
Each tool hands the module its actions with their default shortcuts, and the module binds the shortcut that each action has now.

| Group | Actions | Default shortcuts |
|---|---|---|
| Profiles | Activate profile N, or deactivate it while it is active, and Deactivate the active profile | Command-Option-Shift with 1 to 9, and with 0 |
| Application numbers | Show the windows of application N, and Return every application number to the default | Control-Option with 1 to 9, and with 0 |
| Window search | Show the search of the windows, or close it | Control-Option-Command-Space |
| Window tiling | Fill the screen, and the four halves | Control-Option with Return and the arrows |

"Keyboard shortcuts…" in the menu bar item ◧ opens a window with one row per action, grouped by tool, with each shortcut drawn as its keys, such as ⌃ ⌥ ⌘ Space.
The field at the top filters the actions by their names.

- A click on a shortcut records the next key press with its modifiers as the new shortcut.
  Escape cancels the recording, and Delete removes the shortcut.
  Every shortcut of the tools is off while the window records, so pressing a shortcut of the tools records it.
  A shortcut that macOS acts on before Hammerspoon, such as Command-Space while Spotlight has it, cannot be recorded.
- ✕ leaves the action without a shortcut.
- ↺ gives the action its default shortcut again, and its tooltip names the default.
  A dot after the name of an action marks a shortcut that differs from its default.
- Restore All Defaults gives every action its default shortcut, after a confirmation.

A recorded shortcut that something else uses waits under its row for a choice.

| The recorded shortcut | The choices |
|---|---|
| is the shortcut of another action of the tools | Move it here, which leaves the other action without a shortcut, or Cancel |
| is on in macOS, such as "Select the previous input source" for Control-Space | Turn off the macOS shortcut and use it here, Use it anyway, or Cancel |
| is both | Move it here and turn off the macOS shortcut, Move it here only, or Cancel |
| is Control-Option-Shift-Command with a digit | Cancel alone, because the desktop manager presses it to switch desktops |

The window reads the shortcuts of macOS from System Settings, Keyboard, Keyboard Shortcuts, and also knows the defaults of the screenshot, help and focus shortcuts, which macOS leaves out of its file until they change.
A row whose shortcut macOS also uses shows a warning with the name of the macOS shortcut and a button that turns it off.
Turning a macOS shortcut off runs `tools/disable_macos_shortcut.sh`, which keeps its keys, so turning it on again in System Settings brings the same shortcut back.
The window cannot see the global shortcuts of other applications.

A change applies at once, and the window saves the changes in `~/.hammerspoon/keyboard-shortcuts.json`, which holds only the actions that differ from their defaults.
The file can be edited by hand as well, followed by Reload Config:

```json
{
  "window_search.toggle": { "modifiers": ["ctrl", "alt"], "key": "f" },
  "tiling.top-half": false
}
```

The names of the actions are `profiles.toggle.N`, `profiles.deactivate`, `app_numbers.press.N`, `app_numbers.reset`, `window_search.toggle` and `tiling.<position>`, with the positions of [the section on tiling](#control-option-with-return-or-an-arrow-tiles-the-focused-window).
The modifiers are `ctrl`, `alt`, `shift`, `cmd` and `fn`, and the keys are the names of `hs.keycodes.map`, such as `a`, `5`, `space`, `return` or `left`.

The module leaves out a shortcut in three cases, and a notification and the console name each one.

- A shortcut that an action earlier in the list holds, so the later action has no shortcut.
- Control-Option-Shift-Command with a digit, because the desktop manager presses it to switch desktops.
- A shortcut that names an unknown modifier or key, so the action keeps its default.

The list of application numbers stays open while you hold the modifiers of the shortcut that opened it.
The keys inside the search and the list, such as Escape, Return, Tab and the arrows, are fixed.

## "Search colors…" in the menu bar item picks the colors of the search of the windows

"Search colors…" in the menu bar item ◧ opens a window that picks the five colors.
A preview in the style of the search panel follows each move of a color picker or an opacity slider.
Four presets set all five colors with one click: Blue and amber, the default, Green and gold, Violet and teal, and High contrast.
↺ gives one color its default again, and Restore Defaults gives all five theirs.
Each change is saved with the profiles in `~/.hammerspoon/desktop-manager-state.json`, and the next search shows it without a reload of Hammerspoon.

The setting `search_highlight_colors` in `desktop_manager/default_settings.lua` sets the defaults of the window, with any of the five colors, and the others keep the defaults below.

| Name | Colors the backdrop of | Default |
|---|---|---|
| `selection` | the selected window or application | blue, `{ red = 0.2, green = 0.45, blue = 0.95, alpha = 0.95 }` |
| `hover` | the application under the mouse pointer | white at 16 percent, `{ white = 1, alpha = 0.16 }` |
| `strong_match` | a window or application whose title or name matches the words well | orange at 60 percent, `{ red = 1, green = 0.72, blue = 0.18, alpha = 0.6 }` |
| `medium_match` | a medium match | the same orange at 36 percent |
| `weak_match` | a weak match | the same orange at 18 percent |

A color is a table of `hs.drawing.color`: `red`, `green` and `blue`, or `white`, or `hex`, each with an optional `alpha`, all from 0 to 1.
For example, `search_highlight_colors = { selection = { hex = "#2E8B57", alpha = 0.9 } }` makes the selection green.
A name or a color that the setting cannot use stops the start of the desktop manager with a message in the console.

## Settings of the desktop manager live in `desktop_manager/default_settings.lua`

To change a setting, edit the file and choose Reload Config.
The file writes each choice through its module, such as `list_layout.ROWS` for `rows`.

| Setting | Default | What it sets |
|---|---|---|
| `profile_count` | 9 | the number of profiles |
| `app_number_count` | 9 | the number of application numbers |
| `search_highlight_colors` | blue for the selection, orange for the matches | the default colors behind the selected, hovered and matching items of the search of the windows, under the colors of the window "Search colors…", as [the section on the colors of the search](#search-colors-in-the-menu-bar-item-picks-the-colors-of-the-search-of-the-windows) explains |
| `concealment_method` | `minimize_windows` | how a window goes out of sight: `minimize_windows` minimizes it, and `hide_applications` hides its application once all the windows of the application go out of sight |
| `match_windows_by` | `title` | how a switch pairs a record with an open window: `title` by the title and then the window id, and `id` by the window id, as [the section on switches](#a-switch-changes-only-the-windows-that-differ-from-the-record) explains |
| `missing_window_policy` | `match_title_or_open_new_window` | under `match_windows_by` `id`, what replaces a recorded window that no longer exists, as the same section explains |
| `list_layout` | `columns` | how the list arranges the applications |
| `list_sizing` | `fill_screen` | how the list uses the screen |
| `preview_method` | `blurred_snapshots` | what the list shows beside a title: `blurred_snapshots` a blurred image of the window, or the icon for a window without an image, and `app_icons` the icon of the application |
| `preview_blur` | 1 | how blurred a preview is: 1 keeps full detail, 2 half of it, 4 a quarter |
| `preview_size` | 0.1 by 0.1 | the width and height of a preview, as fractions of the screen in front |
| `list_font_size` | 0.012 | the size of the titles, as a fraction of the height of the screen in front |
| `title_overflow` | `wrap` | what happens to a title longer than its space |
| `title_line_count` | 2 | the most lines of a title under `wrap` |
| `timing` | | the waits and time limits of a switch, in seconds |

The shortcuts are no settings of this file, as [the section on keyboard shortcuts](#keyboard-shortcuts-in-the-menu-bar-item-changes-the-shortcut-of-every-action) explains.

On a screen of 1440 by 875 points, a preview of 0.1 by 0.1 is 144 by 88 points, and a font size of 0.012 is about 10.5 points.
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

### A URL reaches every action of the desktop manager

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
| Clear the saved layouts of profile N, after a confirmation | menu, Clear profile | `action=clear&profile=N` |
| Show the search of the windows | Control-Option-Command-Space | `action=search-windows` |

The numbers belong to the active profile, or to profile 0 while no profile is active.
In a terminal, `open -g "hammerspoon://desktop-manager?action=activate&profile=2"` activates profile 2.

## A switch changes only the windows that differ from the record

Activating a profile does the least work that brings back what the profile recorded.

| The open window | The desktop manager |
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
A switch of profiles removes no desktop, because removing a desktop moves the windows on it and changes what the other profiles recorded.
After a change of monitors, the desktop manager removes only the empty desktops that macOS left, as [the section on the number of desktops of each display](#the-desktop-manager-keeps-the-number-of-desktops-of-each-display-and-removes-the-empty-desktops-that-macos-leaves) says.
A switch shows another desktop for four reasons alone:

- to reach a window that Hammerspoon has not seen;
- to move a window to another screen;
- to open a new window on its recorded desktop;
- to bring the desktop that the profile had in front back to the front.

Hammerspoon can move or minimize a window only after the window has shown once since Hammerspoon started, apart from the minimized windows and the windows of hidden applications.
Before a switch, and before the restore after a change of monitors, the desktop manager therefore shows each desktop that holds a window of a managed application that Hammerspoon has not seen, with the shortcut of the desktop.
The message at the top of every screen reads "Finding the windows on other desktops… please wait".
The desktop manager then shows again the desktops that were in view, and the switch treats those windows as any other.
A window that has shown once stays known until it closes, so later switches show no desktop for it.
A window on a desktop after the tenth stays out of reach, because that desktop has no shortcut, and the alert after the switch names it.

`match_windows_by` chooses how a switch pairs each record with an open window.

| Value of `match_windows_by` | A record takes |
|---|---|
| `title`, the default | the open window of the same application with the same title, the one with the recorded window id first, and the window with the recorded window id when no title matches |
| `id` | the window with the recorded window id, and when that window no longer exists, what `missing_window_policy` chooses |

Under `title`, a window keeps its record when its application reopens it with a new window id, such as a window of Visual Studio Code after the application restarts, or when it moved to another desktop before Hammerspoon saw it.
A window whose title changed, such as a browser window on another tab, keeps its record through its window id, unless another window took the title.
A record with an empty title, such as the record of a window that macOS listed before Hammerspoon had the permission for Screen Recording, matches by its window id alone.

Under `id`, macOS gives a window that its application reopens a new window id, so `missing_window_policy` chooses what replaces a recorded window in sight that no longer exists.

| Value of `missing_window_policy` | The desktop manager |
|---|---|
| `match_title_or_open_new_window`, the default | takes an open window of the same application with the same title, and opens a new window when no title matches |
| `open_new_window` | opens a new window of the same application |

Under the default, the desktop manager also treats an unrecorded window as the reopened copy of a closed recorded window of the same application with the same title.
Position and size play no part, because the desktop manager sets them on the window it takes, and because macOS opens a new window at the place of the last closed one.
A reopened window whose title changed, such as a browser window on another tab, counts as a new window.

The new window comes from the first of three sources that gives one:

1. A window that a launch of the application opened during the same switch, when the application was not running.
2. The menu item "New Window" of the application, or "New Finder Window" of the Finder.
3. A reopen of the application, as a click on its icon in the Dock sends, which shows the main window of an application such as Calendar.

The desktop manager leaves out Command-N, because Calendar, Mail, Notes and Slack create an event, a message or a note with it.
A window opens on the desktop that shows, so the desktop manager shows the recorded desktop first, and then sets the recorded frame.
The records of every profile then name the new window.
An application that opens no new window within ten seconds is reported in a notification.

The desktop manager saves the profiles, their records and their application numbers in `~/.hammerspoon/desktop-manager-state.json`.
A file that the desktop manager cannot read is moved aside to a name that ends in `.unreadable-` and the time, and the desktop manager starts a new state.

## Hammerspoon and macOS 27.0.1 limit what the desktop manager can do

The functions of Hammerspoon 1.1.1 that move a window to another desktop, or that switch, add or remove desktops, fail on macOS 27.0.1.
The issues [#3903](https://github.com/Hammerspoon/hammerspoon/issues/3903) and [#3897](https://github.com/Hammerspoon/hammerspoon/issues/3897) of Hammerspoon report the failures.
The desktop manager works around them as follows.

- macOS 27.0.1 unminimizes a window onto the desktop it was minimized on, also when another desktop shows, as the log of the desktop manager showed on 2026-10-10.
  A switch therefore brings minimized windows back without switching desktops.
  For the same reason, a window on another desktop of its screen stays there, and the console notes it.
  A window moves to another screen when the desktop manager sets its frame there.
- A desktop switch presses Control-Option-Shift-Command with the number of the desktop, and with 0 for the tenth desktop.
  Mission Control numbers the desktops of all screens in one sequence, so desktops after the tenth cannot be reached.
  Ten desktops across all screens are enough for most setups, such as five on the built-in display and five on an external monitor.
  Before the press, the desktop manager reads whether macOS has the shortcut on.
  When the shortcut is off, the desktop manager runs `tools/enable_desktop_shortcuts.sh`, which turns on the shortcuts 1 to 10, and then presses.
  The shortcut of the tenth desktop is the entry 127 of the shortcuts of macOS, which no test on macOS 27.0.1 has confirmed yet.
  When the script fails, the desktop manager reports the desktop at once, with an alert and a notification.
- Adding a desktop presses the add button of Mission Control through accessibility, under the process WindowManager, which worked on 2026-10-10.
  Removing a desktop asks the desktop in the list of Mission Control to remove itself, as `hs.spaces.removeSpace` does, which no test on macOS 27.0.1 has confirmed yet.
  Mission Control opens for a moment during the addition and the removal.
  When the button or the desktop is not found, the desktop manager notifies you, and you add or remove the desktop in Mission Control.
- Accessibility reaches a window once its desktop has shown after Hammerspoon started, and it always reaches the minimized windows and the windows of hidden applications.
  The records, the search and the list of Control-Option find the other windows in the list of all windows of macOS, which `desktop_manager/macos/list_server_windows.js` prints through `osascript`.
  A switch shows their desktops first, as [the section on switches](#a-switch-changes-only-the-windows-that-differ-from-the-record) says.
  The desktop manager runs the script at the start, at each change of desktop, once a minute and when the search opens, in about 0.2 seconds each time.
  Such a window counts when it lies on a desktop out of view, belongs to an application with a Dock icon, and measures at least 100 by 50 points, which leaves out most of the hidden windows that applications keep.
  Its title needs the permission for Screen Recording, and without it the window shows as "untitled window".
  Choosing such a window shows its desktop with the shortcut of the desktop, so a window on an eleventh desktop cannot be reached.
- The window filter of Hammerspoon drops a window whose subrole changes while its application is hidden, as the window of Calendar does.
  The desktop manager looks such windows up among all windows of macOS.

### The desktop manager waits for four pull requests of Hammerspoon

On 2026-10-13, four open pull requests of Hammerspoon would lift some of these limits once a release of Hammerspoon holds them.
None of them is in Hammerspoon 1.1.1, the latest release, of 2026-02-26.

| Pull request | What it changes in Hammerspoon | What the desktop manager would gain |
|---|---|---|
| [#3889](https://github.com/Hammerspoon/hammerspoon/pull/3889) | `hs.spaces.moveWindowToSpace` moves a window by its id through a private function of macOS, which the author tested on macOS 26.5 and a user reported working on macOS 27.0.1 | a move of any window to any desktop of its screen, also a window that Hammerspoon has not seen, without showing its desktop first |
| [#3904](https://github.com/Hammerspoon/hammerspoon/pull/3904) | `hs.spaces` finds Mission Control under the process WindowManager of macOS 27 | `hs.spaces.gotoSpace`, `addSpaceToScreen` and `removeSpace` instead of the own module of Mission Control, and switches to the desktops after the tenth |
| [#3859](https://github.com/Hammerspoon/hammerspoon/pull/3859) and [#3866](https://github.com/Hammerspoon/hammerspoon/pull/3866) | `hs.eventtap.event` writes the fields of an event as floating-point numbers | desktop switches through the swipe events of the Dock, in about 40 milliseconds and without the slide |

The knowledge item `knowledge-bases/yujun-knowledge-base/macos/moving-windows-between-desktops.md` of the ai-workspace compares the ways to move a window between desktops.

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

## Diagnostics in the Hammerspoon console show what the desktop manager reads

`hs -c "desktop_manager:print_diagnostics()"` prints what the desktop manager reads of the screens, desktops and windows, and which profiles recorded each window, and changes nothing.
"Print diagnostics to the console" in the menu bar item prints the same into the Hammerspoon console.
Each switch writes its plan and its duration to the console.
Each desktop switch also writes how long it waited for the release of the modifiers and how long macOS took to report the new desktop.
The rest of a switch is the animation of macOS, which "Reduce motion" in step 7 of the installation shortens.

## Control-Option with Return or an arrow tiles the focused window

The window tiling sets the frame of the focused window to a part of its screen, with the default shortcuts of Rectangle.

| Keys | The focused window takes |
|---|---|
| Control-Option-Return | the whole screen |
| Control-Option-Left | the left half of the screen |
| Control-Option-Right | the right half |
| Control-Option-Up | the top half |
| Control-Option-Down | the bottom half |

The tiling acts on the focused window when it is a standard window.
When the focus is in a panel, such as the search window of Asyar, the tiling acts on the frontmost standard window, and gives it the focus.
The screen is the one that holds the largest part of the window, without the menu bar and the Dock.
The window takes its new frame at once, without an animation.
Hammerspoon receives the shortcuts before the application in front, so the shortcuts work in every application, also before the application has built its Window menu.
An application loses its own shortcuts on these keys, as under Rectangle.
On 2026-10-11, the enabled shortcuts of macOS used Control-Option only with Space, which selects the next input source.
VoiceOver uses Control-Option with the arrows while it is on.

The desktop manager uses Control-Option with the numbers, and the window tiling uses Control-Option with Return and the arrows, so the two tools take different keys.

### Settings of the window tiling live in `window_tiling/default_settings.lua`

To change a setting, edit the file and choose Reload Config.

| Setting | Default | What it sets |
|---|---|---|
| `url_event_name` | `window-tiling` | the host of the URLs, as below |

### The Asyar extension in `asyar-window-tiling/` adds the item Fill Window

The extension adds one item to the search of Asyar, Fill Window, which fills the screen with the window behind the search window of Asyar.
The extension leaves the halves to the window management that Asyar has built in.
The manifest, `asyar-window-tiling/manifest.json`, gives the extension one permission, `shell:open-url` for the URLs that start with `hammerspoon://`.

Setting up the extension takes two steps, with Node and npm installed.

1. Run `npm install` in `asyar-window-tiling/`.
2. Run `make link-asyar-window-tiling` in the folder of this repository.

Quit Asyar and start it again, so that it loads the extension.

### A URL tiles the focused window from outside Hammerspoon

The URL `hammerspoon://window-tiling?position=<position>` takes one of the positions `fill`, `left-half`, `right-half`, `top-half` and `bottom-half`.
In a terminal, `open -g "hammerspoon://window-tiling?position=left-half"` puts the focused window on the left half of its screen.
A URL with another position shows a notification and moves no window.

## The Asyar extension in `asyar-trash/` opens and empties the Trash

The extension adds two items to the search of Asyar.

| Item | Enter |
|---|---|
| Trash | opens the Trash in a window of the Finder |
| Empty Trash | shows the confirmation of Finder, Empty Trash, and erases the items in the Trash after you choose Empty Trash |

- The confirmation takes its words from the Finder, in the language of macOS, and shows the icon of the Finder.
- Cancel or Escape erases nothing.
- With an empty Trash, Empty Trash shows no confirmation, and a notification says "The Trash is empty."
- The Finder adds no second confirmation, because the extension turns off its setting "Show warning before emptying the Trash" for the erase alone and then restores your value.
  When an erase stops halfway, check that setting in Finder, Settings, Advanced.

Each item runs one AppleScript through `/usr/bin/osascript`, which counts, asks, erases and reports by itself, because Asyar gives the output of a program to no background command, as the knowledge item `knowledge-bases/yujun-knowledge-base/macos/asyar-background-workers.md` of the ai-workspace says.
The notification of an empty Trash and of a failure in a script therefore comes from `osascript`, and macOS shows it under the name Script Editor.

| Permission | Use |
|---|---|
| `shell:spawn` | runs `/usr/bin/osascript`, which Asyar asks you to trust on first use |
| `notifications:send` | tells you when Asyar does not start the script |

On first use, macOS also asks whether Asyar may control the Finder, and may ask whether Script Editor may send notifications.

Setting up the extension takes two steps, with Node and npm installed.

1. Run `npm install` in `asyar-trash/`.
2. Run `make link-asyar-trash` in the folder of this repository.

Quit Asyar and start it again, so that it loads the extension.

## The code of each tool splits into a tested core and a macOS layer

| Folder or file | Content |
|---|---|
| `init.lua` | the file that Hammerspoon loads, which starts the center of the shortcuts and the two tools |
| `keyboard_shortcuts/core/` | the registry of the shortcuts of every tool, with the defaults, the overrides and the shortcuts left out, and the shortcuts of macOS that a shortcut collides with |
| `keyboard_shortcuts/macos/` | the center that binds the shortcuts and saves the overrides, the reading and turning off of macOS shortcuts, and the window "Keyboard shortcuts…" |
| `desktop_manager/core/` | the decisions of the desktop manager: monitor configurations, window matching, profile records, the pool of managed applications, plans for concealing, restoring and opening missing windows, application numbers, the search of the windows and its scores, the windows of macOS that accessibility does not reach, URL commands |
| `desktop_manager/macos/` | the calls of the desktop manager to Hammerspoon: reading screens, desktops and windows, the list of all windows of macOS and its script, switching desktops, opening new windows, switching to the application of a number, the panel of the search, Mission Control, the menu bar item, the message during a switch, the window of the managed applications and the controller |
| `window_tiling/core/` | the positions of the window tiling and the frame of each position on a screen |
| `window_tiling/macos/` | the controller of the window tiling, which hands its actions to the center of the shortcuts, binds its URLs and sets the frame of the focused window |
| `tests/` | unit tests of the cores, tests of whole switches and of the tiling controller against `tests/fake_hammerspoon.lua` |
| `tools/` | the generators of the launcher scripts and of the settings of the Asyar extension of the desktop manager, and the scripts that turn the desktop shortcuts of macOS on and one shortcut of macOS off |
| `launcher-scripts/` | the scripts for Asyar and Raycast, written by the generator |
| `asyar-extension/` | the Asyar extension of the desktop manager, in TypeScript, with its manifest, its worker and the unit tests of its items |
| `asyar-window-tiling/` | the Asyar extension of the window tiling, in TypeScript, with its manifest, its worker and the unit tests of its URL |
| `asyar-trash/` | the Asyar extension that opens and empties the Trash, in TypeScript, with its manifest, its worker and the unit tests of its scripts |

The two tools share the modules of `keyboard_shortcuts/` alone.
The modules of `desktop_manager/core/`, `window_tiling/core/` and `keyboard_shortcuts/core/` call no Hammerspoon function, so `lua` 5.4 runs their tests outside Hammerspoon.
The fake of Hammerspoon unminimizes a window onto its own desktop, as macOS 27.0.1 does, and a test can make it unminimize onto the desktop that shows.
The tests check the logic of the tools, and say nothing about the behaviour of macOS.

`make check` checks the syntax with `luac -p`, lints with `luacheck`, checks the formatting with `stylua --check`, runs the tests, and compares the generated files with their generators.
`make format` formats the code with `stylua`.
The programs of these commands come from Homebrew: `lua@5.4`, `luacheck`, `stylua` and `lua-language-server`.

`make check-asyar-extension` checks the types of the extension of the desktop manager, runs its unit tests, runs `asyar validate` of the SDK of Asyar, and builds it.
`make check-asyar-window-tiling` does the same for the extension of the window tiling, and `make check-asyar-trash` for the extension of the Trash.
After a change to an extension, run its `make link-...` target again, or `npm run build` in its folder, because Asyar loads the built files through the link.

Two generators take the numbers of profiles and of applications from `desktop_manager/default_settings.lua`.
`make launcher-scripts` runs `tools/write_launcher_scripts.lua`, which writes the scripts.
`make asyar-extension-settings` runs `tools/write_asyar_extension_settings.lua`, which writes `asyar-extension/src/settings.generated.json`.
Run them after a change of the settings, because `make check` fails when a generated file differs from the output of its generator.

The code follows the [LuaRocks style guide](https://github.com/luarocks/lua-style-guide), read on 2026-10-10, with four departures.

- Indentation is four spaces, as in the Lua extensions that Hammerspoon 1.1.1 ships, where the guide uses three.
- Types are written as annotations of lua-language-server, such as `---@param`, where the guide uses LDoc, because the language server checks them.
- Misuse of a function raises `error` with a message that states the fact and the value, where the guide uses `assert`.
- `init.lua` sets one global per tool, `desktop_manager` and `window_tiler`, because Hammerspoon stops the hotkeys and watchers that Lua garbage-collects, and because the command-line tool `hs` reaches the controllers through them.

Lines are at most 100 characters long, as `stylua.toml` and `.luacheckrc` set.
