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
The switch also removes the empty desktops that profile 2 does not hold, and shows on each screen the desktop that it showed when profile 2 last recorded it.
Command-Option-Shift-2 again deactivates profile 2, and macOS manages the windows as usual.

The window tiling puts the focused window on the whole screen or on one half of it, with Control-Option and Return or an arrow, as [Rectangle](https://rectangleapp.com) does.

Each tool has an extension for the launcher [Asyar](https://asyar.org).
A third Asyar extension, in `asyar-trash/`, opens the Trash and empties it after a confirmation.
The scripts in `launcher-scripts/` run the actions of the desktop manager from Asyar or Raycast.

The tools run on macOS 27.0.1 with a build of Hammerspoon that holds [pull request #3889](#a-build-of-hammerspoon-with-pull-request-3889-moves-windows-between-the-desktops-of-a-screen), the versions they were developed on.
`requirements.md` states what the tools must do.

## Install the tools in six steps

1. Build Hammerspoon with pull request #3889, put it in `/Applications`, and start it, as [the section on the build](#a-build-of-hammerspoon-with-pull-request-3889-moves-windows-between-the-desktops-of-a-screen) says.
2. Clone this repository into a folder of your choice, and run `make install-loader` in that folder.
   The command writes `~/.hammerspoon/init.lua` with the one line `dofile("<folder>/init.lua")`.
   When `~/.hammerspoon/init.lua` exists already, the command leaves it unchanged, and you add the line to it yourself.
3. Click the hammer icon in the menu bar and choose Reload Config.
4. In System Settings, Privacy & Security, Accessibility, turn on Hammerspoon.
5. In System Settings, Desktop & Dock, Mission Control, keep "Displays have separate Spaces" on, and turn "Automatically rearrange Spaces based on most recent use" off.
   The desktop manager finds a desktop by its position, and a rearrangement moves the positions.
6. Shorten the animations, if you like.
   In System Settings, Desktop & Dock, set "Minimize windows using" to Scale Effect.
   In System Settings, Accessibility, Display, turn on "Reduce motion", which also shortens the openings of Mission Control.

The menu bar then shows `◧`, and `◧ 2` while profile 2 is active.
The menu bar shows `◧ 2 paused` while profile 2 is paused, as [the section on the pause](#the-first-start-of-hammerspoon-soon-after-a-login-pauses-the-active-profile) says.
The previews in the list of windows also need the permission for Screen Recording, as [the section on the previews](#the-previews-of-the-list-need-the-permission-for-screen-recording) explains.

## Command-Option-Shift with a number activates, switches and deactivates profiles

| Keys | Effect |
|---|---|
| Command-Option-Shift-N, for N from 1 to 9 | activates profile N, or switches to it from the active profile |
| Command-Option-Shift-N while profile N is active and not paused | deactivates profile N |
| Command-Option-Shift-N while profile N is paused | restores the layout of profile N, as an activation does, and ends the pause |
| Command-Option-Shift-0 | deactivates the active profile |

While a switch works, a message at the top of every screen names its step, and it disappears when the switch ends.
The steps read "Arranging Profile 2… please wait", "Adding 2 desktops to built-in… please wait", "Showing desktop 2 of built-in… please wait" and "Removing 2 empty desktops from built-in… please wait".
Leave the windows and the desktops alone until then, because the desktop manager may move a window again after you have moved it, or open a window on the desktop that you switched to.
A profile shortcut pressed during a switch gives the alert "Desktop Manager is still switching", and the switch goes on.
A switch that has not ended after `busy_watchdog_seconds` of `timing`, 90 seconds by default, stops with an alert, so that the next switch can start.
The remaining steps of the stopped switch then do nothing, and Mission Control closes when it shows.

The desktop manager shows, adds and removes desktops by pressing the elements of Mission Control.
Mission Control opens in sight for about a second for each press or edit, and it may cover the message at the top of the screen while it shows.
Mission Control opens once you release the modifier keys, because Option held in Mission Control shows the buttons that remove desktops.
When a key stays held for `modifier_release_timeout_seconds` of `timing`, 3 seconds by default, Mission Control stays closed, and the alert after the switch says so.

While no profile is active, macOS manages the windows as usual, also when the monitors change: the desktop manager then moves no window and removes no desktop.

A profile keeps one record per monitor configuration.
The record holds the number of desktops of each screen, the desktop that each screen shows, the screen that has the focus, and every window of a managed application while the profile is active, on every desktop.
A window on a desktop that has not shown since Hammerspoon started is recorded from the list of all windows of macOS, with its desktop, its frame and its title.
Each window is recorded as in sight, on a desktop at its frame, or as out of sight.
A window is out of sight when it is minimized or its application is hidden.
The record names a window by its application, its window id and its title.
Windows do not belong to profiles, and two profiles may record the same window.
A record saved before the records held the desktop of each screen keeps its desktop in front as the desktop that its screen shows and as the screen of the focus.
Its number of desktops of a screen becomes at most the larger of two numbers.
One is the number that the desktop manager tracks for the display, as the next section says, and the other is the highest desktop that the record names for a window of that screen.

The desktop manager updates the record of the active profile at four times:

- two seconds after a window opens, closes, moves, minimizes or changes its title;
- once a minute;
- at the end of a switch;
- before a switch to another profile.

None of the four updates runs while the active profile is paused, as [the section on the pause](#the-first-start-of-hammerspoon-soon-after-a-login-pauses-the-active-profile) says.

When the monitors change while a profile is active and not paused, the desktop manager waits for macOS to move the windows.
The wait lasts `screen_settle_seconds` of `timing`, 3 seconds by default, and the message at the top of every screen says so.
The wait starts again while a switch or a press of the list or the search runs, so the restore follows once that work has ended.
The message of the wait then shows again.
A change during the restore of an earlier change starts the wait again as well, and the record of the profile stays as it was until the restore of the last change has ended.

- When the profile is deactivated during the wait, the message closes, and the windows and the desktops stay with macOS.
- When the new configuration is one that the active profile recorded, the desktop manager then restores that record, and the message stays until the restore ends.
  The restore moves the windows that the record holds, shows the desktop that each screen showed, and removes the desktops beyond the numbers of the record, as the next section says.
  It minimizes no window and opens no new window, because the record predates the windows that you opened under the other configuration.
- When the new configuration is new to the profile, an alert says that the windows stay where macOS put them, and the profile starts recording the new configuration.
  The desktop manager then removes the empty desktops that macOS left, as the next section says.

The row "Same monitor configuration by" of [the window "Settings…"](#settings-in-the-menu-bar-item-changes-the-behaviour-of-the-desktop-manager-while-it-runs) sets when two monitor configurations count as the same.

| Choice of "Same monitor configuration by" | Configurations that count as different |
|---|---|
| Number of external monitors, the default | the built-in display alone, the built-in display with one external monitor, two external monitors, and so on |
| Name of each external monitor | also the built-in display with `LG TV SSCR2` and the built-in display with `DELL U2720Q` |

Below the profiles, the menu bar item groups the entries that deactivate the active profile, rename it, update its record at once and clear a profile.
The first three name the active profile, such as Deactivate “Writing”, and the first two are dimmed while no profile is active.
"Application numbers" follows in a group of its own, and the last group opens the windows "Settings…", "Managed applications…" and "Keyboard shortcuts…" and prints diagnostics.

### A profile can leave a monitor configuration to macOS

Each profile arranges every monitor configuration until you untick the configuration for it in [the window "Settings…"](#settings-in-the-menu-bar-item-changes-the-behaviour-of-the-desktop-manager-while-it-runs).
For example, profile 1 may arrange the built-in display with one external monitor and leave the built-in display alone to macOS.
While the active profile leaves the configuration of the monitors to macOS, the desktop manager acts as while no profile is active.
Its records stay as they are, a change of the monitors leaves the windows where macOS puts them, and every desktop stays.
A change of the monitors into such a configuration shows an alert, such as "Profile 1 leaves built-in to macOS".
A change back to a configuration that the profile arranges restores the record of that configuration, as the section above says.

A switch to a profile that leaves the configuration to macOS makes the profile active, shows the same alert, and leaves every window and every desktop where it is.
A switch away from such a profile records nothing for it.
A switch to a profile that arranges the configuration restores its record as usual, and a profile without a record of the configuration starts recording it.
"Update the record now" in a configuration that the active profile leaves to macOS records nothing and shows the alert.
A tick for the active profile under the configuration now starts its records from the windows as they are.
The application numbers of Control-Option and the search of the windows keep working in every configuration.

### The first start of Hammerspoon soon after a login pauses the active profile

After a restart of the Mac or a logout, macOS reopens the windows at the next login with new window ids and at places of its own.
The updates of the active profile would then replace its record with that arrangement within about a minute.
When Hammerspoon starts for the first time after a login, and less than `pause_after_login_seconds` after it, 300 seconds by default, the desktop manager keeps the active profile and pauses it.
A restart of the Mac ends with a login as well, so the pause covers both.
The time counts from the minute of the login that macOS records, as `who` gives it, so a Reload Config later in the day keeps the updates of the profile going.
The state file keeps the login that the last start of Hammerspoon saw, so a second start under the same login pauses nothing either.
When macOS gives no login, the time counts from the start of macOS and leaves out the time asleep, as `hs.timer.absoluteTime()` gives it, and only the first start after a start of macOS pauses.
The value 0 turns the pause off.

While profile 2 is paused, no update changes its record or its application numbers, and a change of the monitors leaves the windows and the desktops to macOS.
A press of the list or the search records no desktop shown.
Control-Option with a number reaches the applications of the numbers of profile 2.
The console of Hammerspoon names the pause at each start, and the line of the start that pauses gives the seconds since the login, or since the start of macOS when no login was read.
The state file keeps the pause, so a reload keeps it, also after `pause_after_login_seconds` and also with the value 0.

| Action during the pause | Effect |
|---|---|
| Command-Option-Shift-2, its URL, its Asyar item or its item in the menu bar item | restores the layout of profile 2 as an activation does, and the updates go on from the end of the restore |
| Command-Option-Shift with another number | switches to that profile without the update of profile 2 before the switch |
| Command-Option-Shift-0 | deactivates profile 2 without an update |
| "Save layout of “Profile 2” and end the pause" in the menu bar item, or the URL `action=save` | records the windows as they are and ends the pause |
| "Clear a profile" on profile 2 | empties profile 2, which records the windows from its next update on |
| "Return N to the default" or Control-Option-0 | gives the default numbers of the record of profile 2 for the monitor configuration, and Control-Option-0 keeps the default numbers that profile 2 had |

A rename, a number given by hand, the managed applications and the choice of the same monitor configuration work as usual.
A switch that stops after `busy_watchdog_seconds` before it takes windows out of sight leaves the pause as it was.
The menu bar item shows `◧ 2 paused` with a dash at profile 2, and the diagnostics give "active profile: 2, paused".

### A profile holds the number of desktops of each screen, and a restore removes the empty desktops beyond it

When a monitor disconnects, macOS removes the first desktop of the monitor and moves its other desktops, with their windows, to the end of the built-in display.
When the monitor returns, macOS gives it back one desktop, and the others stay on the built-in display.
The desktop manager brings each screen back to the number of desktops that the profile holds, so that such desktops do not pile up on the built-in display.

A profile records the number of desktops of each screen at each update.
A desktop that you add in Mission Control therefore joins the profile, and so does a desktop that stays because a window keeps it.
The first record of a monitor configuration also holds the desktops that macOS moved there at the change, with their windows, and a later change to that configuration brings them back.
A switch to a profile with a layout for the monitors, and the restore after a change of monitors, add the desktops that a screen lacks before the windows move.
They remove the desktops beyond the number after the windows are in place.

The removal takes each desktop beyond the number that is out of view and that no window keeps, from the end of the screen, where macOS puts the desktops it moves.
The removal on a screen stops at the first desktop from the end that stays, so that the desktops below it keep their numbers, and the console of Hammerspoon notes the empty desktops that stay.
A window of an application that the desktop manager leaves to macOS keeps its desktop, also while it is minimized or its application is hidden.
A window of a managed application keeps its desktop only while it is in sight, because macOS moves a minimized window to another desktop when its desktop goes, and the window stays minimized.
No test on macOS 27.0.1 has confirmed that move yet, and check 4 of [the checks of the build](#four-commands-check-what-the-desktop-manager-assumes-of-the-build-and-of-macos-2701) tests it.
A window that Hammerspoon has not seen keeps its desktop when the list of all windows of macOS places it there, as [the section on the limits of macOS](#hammerspoon-and-macos-2701-limit-what-the-desktop-manager-can-do) says of such windows.
A window that macOS shows on every desktop keeps none of them.
Right before it removes a desktop, the desktop manager checks again that the desktop is out of view and that no window that Hammerspoon knows keeps it.
A desktop that fails the check stays, with a line in the console.

The removals on every screen go in one opening of Mission Control, which ends with the press on the recorded desktop of the screen that has the focus.
The message at the top of every screen then reads "Removing 2 empty desktops from built-in… please wait".
When the screen of the focus shows a desktop beyond the number, its recorded desktop shows first, in an opening of its own.

For a monitor configuration that the active profile has no layout for, the desktop manager tracks the number of desktops of each display.
The tracked number follows the desktops that you add or remove in Mission Control while the monitors stay connected.
The desktops that macOS moves at a change of monitors leave the number as it was.
A display starts with the desktops it has when the desktop manager first sees it.
The display goes by its name in the monitor configuration, such as `built-in` or `external 1`, so two monitors that count as the same configuration share a number.
A monitor that takes the place of another therefore starts with the number of the other.
After a change of monitors to such a configuration, the desktop manager removes the desktops beyond the tracked numbers by the same rule.
"Print diagnostics" in the menu bar item shows the tracked numbers and the numbers of the active profile.

For example, the built-in display has 3 desktops and a Dell monitor has 4, and the active profile has a layout for both monitor configurations.
When the Dell monitor disconnects, the built-in display has 6 desktops.
The restore of the active profile places its windows on the built-in display, and then removes the moved desktops that no window keeps, from the end up to the first that a window keeps.
When the Dell monitor returns with one desktop, the restore adds 3 desktops to it and moves the windows of the profile back to them.
The desktop manager then removes the desktops left empty on the built-in display, which has 3 desktops again when the profile held every window of the moved desktops.
A window of an application that the desktop manager leaves to macOS stays on its moved desktop, and that desktop stays too, with the desktops below it.
Before the restore, the desktop manager moves each window of the profile that Hammerspoon has not seen by its id to the desktop in view of its screen, so that such a window moves to the monitor as well.

### "Clear a profile" in the menu bar item, or Control-Option-Command with the number, empties a profile

"Clear a profile" lists every profile, and a profile without a saved layout shows dimmed.
Control-Option-Command with the number of a profile clears that profile, after the same confirmation.
After you confirm, the profile forgets the desktops and windows it saved for every monitor configuration, and keeps its name and its application numbers.
A cleared profile acts as a new one: activating it takes the windows that other profiles recorded out of sight, as `concealment_method` sets, and brings back nothing.
The windows that no profile recorded stay in sight, and the profile records them at its next update.
A profile with a layout for the monitors instead takes every window of a managed application out of sight that it did not record in sight.
A cleared active profile stays active and records the windows from its next update on.
A cleared paused profile ends its pause.

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
The windows of a hidden application show as the setting `hidden_application_windows` sets, and by default not at all, as [the section on the settings](#settings-of-the-desktop-manager-live-in-desktop_managerdefault_settingslua) explains.
The list also holds the windows on the desktops that you have not visited since Hammerspoon started.
Bringing a window on another desktop to the front shows that desktop first, through a press in Mission Control, with the message "Showing desktop 2 of built-in… please wait".
The record of the active profile takes that desktop at once as the desktop that its screen shows, so that a change of monitors before the next update brings it back.
A window in full screen on a space of its own shows through a press on the thumbnail of that space in the same way.
An application without windows shows "no window, a new one opens", and gets a new window from the same sources that replace a closed window at a switch, with the message "Opening a window of Notes… please wait".
Under the default `leave_out`, a hidden application shows "hidden, a press unhides it".
Releasing on it brings the main window of the application, or else its first window, to the front without a new window.
When that window lies on another desktop, the desktop shows first through Mission Control, with the message "Showing desktop 2 of built-in… please wait".
The desktop shows before the unhide, because accessibility may lose a window on a desktop that has not shown since Hammerspoon started once its application unhides.
When that window lies on the desktop in view, the message reads "Unhiding Microsoft Word… please wait".
The message stays while the application unhides and during the wait that follows.
The desktop manager waits up to `window_reach_timeout_seconds` of `timing` until a window of the application is a standard window again, because a window may report the subrole `AXDialog` while its application is hidden.
When no window of the application is a standard window in time, an alert names the application.
A hidden application that keeps no window gets a new window from the same sources.
A window chosen in the list or the search during a switch, a restore or another press gives "Desktop Manager is still switching" and does nothing, so that the message of that work stays.
Every action on a profile gives the same alert while a press of the list or the search shows a desktop, unhides an application or opens a window.
The action may come from a shortcut, the menu bar item, Asyar or a URL.

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
| Return | brings the selected window to the front, and shows its desktop first through Mission Control when another desktop shows |
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
The windows of hidden applications show in the panel as the setting `hidden_application_windows` sets, and by default not at all.
On 2026-10-12, the shortcuts of macOS used Space with Control and with Control-Option alone, and Asyar used Command-Space, so Control-Option-Command-Space was free.

## "Keyboard shortcuts…" in the menu bar item changes the shortcut of every action

Every global shortcut of the desktop manager and of the window tiling is in one list, which one module binds, `keyboard_shortcuts/macos/shortcut_center.lua`.
Each tool hands the module its actions with their default shortcuts, and the module binds the shortcut that each action has now.

| Group | Actions | Default shortcuts |
|---|---|---|
| Profiles | Activate profile N, restore it while it is paused, or deactivate it while it is active, and Deactivate the active profile | Command-Option-Shift with 1 to 9, and with 0 |
| Profiles | Clear profile N, after a confirmation | Control-Option-Command with 1 to 9 |
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

The window reads the shortcuts of macOS from System Settings, Keyboard, Keyboard Shortcuts, and also knows the defaults of the screenshot, help and focus shortcuts, which macOS leaves out of its file until they change.
A row whose shortcut macOS also uses shows a warning with the name of the macOS shortcut and a button that turns it off.
Turning a macOS shortcut off runs `tools/disable_macos_shortcut.sh`, which keeps its keys, so turning it on again in System Settings brings the same shortcut back.
The window cannot see the global shortcuts of other applications.

The desktop manager no longer uses the macOS shortcuts "Switch to Desktop 1" to "Switch to Desktop 10", which earlier versions of the desktop manager turned on as Control-Option-Shift-Command with 1 to 9 and 0.
Turn them off in System Settings, Keyboard, Keyboard Shortcuts, Mission Control, or with the button of this window when a recorded shortcut collides with one of them.

A change applies at once, and the window saves the changes in `~/.hammerspoon/keyboard-shortcuts.json`, which holds only the actions that differ from their defaults.
The file can be edited by hand as well, followed by Reload Config:

```json
{
  "window_search.toggle": { "modifiers": ["ctrl", "alt"], "key": "f" },
  "tiling.top-half": false
}
```

The names of the actions are `profiles.toggle.N`, `profiles.deactivate`, `profiles.clear.N`, `app_numbers.press.N`, `app_numbers.reset`, `window_search.toggle` and `tiling.<position>`, with the positions of [the section on tiling](#control-option-with-return-or-an-arrow-tiles-the-focused-window).
The modifiers are `ctrl`, `alt`, `shift`, `cmd` and `fn`, and the keys are the names of `hs.keycodes.map`, such as `a`, `5`, `space`, `return` or `left`.

The module leaves out a shortcut in two cases, and a notification and the console name each one.

- A shortcut that an action earlier in the list holds, so the later action has no shortcut.
- A shortcut that names an unknown modifier or key, so the action keeps its default.

The list of application numbers stays open while you hold the modifiers of the shortcut that opened it.
The keys inside the search and the list, such as Escape, Return, Tab and the arrows, are fixed.

## "Settings…" in the menu bar item changes the behaviour of the desktop manager while it runs

"Settings…" in the menu bar item ◧ opens a window with one row per setting that the column "In Settings…" of [the table of the settings](#settings-of-the-desktop-manager-live-in-desktop_managerdefault_settingslua) marks.
The window has four sections.

| Section | Settings |
|---|---|
| Switching profiles | `unmatched_window_action`, which opens a new window for a recorded window that is no longer open or removes the window from the profile, `match_windows_by`, `missing_window_policy` and `concealment_method` |
| Monitors and login | "Same monitor configuration by" and `pause_after_login_seconds` |
| What the list and the search show | `hidden_application_windows`, `preview_method`, `preview_size` and `preview_blur` |
| Layout of the list | `list_layout`, `list_sizing`, `list_font_size`, `title_overflow` and `title_line_count` |

A choice offers the values of the setting by name, a number has a slider, and the size of a preview has a slider for its width and one for its height.
Below the four sections, the table "Monitor configurations that each profile arranges" has one row per profile and one column per monitor configuration that a profile recorded or left to macOS, with the configuration now marked "(now)".
A tick arranges the configuration for the profile, and no tick leaves it to macOS, as [the section on such a configuration](#a-profile-can-leave-a-monitor-configuration-to-macos) says.
Each change is saved with the profiles in `~/.hammerspoon/desktop-manager-state.json`, over the value of `desktop_manager/default_settings.lua`, and the next switch, list or search uses it without a reload of Hammerspoon.
`pause_after_login_seconds` counts from the next start of Hammerspoon.
↺ on a row returns the setting to the value of the file, and a later edit of the file then changes it.
A change during a switch, a restore or a press of the list or the search gives "Desktop Manager is still switching" and does nothing, because the work reads the settings at several of its steps.
A saved choice that the checks of the settings refuse, such as after an edit of the file, is left out at the start, with a line in the console of Hammerspoon.
The URL `action=open-settings` and the action "Open the window Settings of the desktop manager" in "Keyboard shortcuts…", which has no default shortcut, open the window as well.

## "Search colors…" in the window "Settings…" picks the colors of the search of the windows

The button "Search colors…" of the window "Settings…" opens a window that picks the five colors.
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
The window "Settings…" changes the settings that the column "In Settings…" marks while the desktop manager runs, over the values of the file, as [its section](#settings-in-the-menu-bar-item-changes-the-behaviour-of-the-desktop-manager-while-it-runs) explains.
The file writes each choice through its module, such as `list_layout.ROWS` for `rows`.

| Setting | Default | In Settings… | What it sets |
|---|---|---|---|
| `profile_count` | 9 | no | the number of profiles |
| `app_number_count` | 9 | no | the number of application numbers |
| `search_highlight_colors` | blue for the selection, orange for the matches | no | the default colors behind the selected, hovered and matching items of the search of the windows, under the colors of the window "Search colors…", as [the section on the colors of the search](#search-colors-in-the-window-settings-picks-the-colors-of-the-search-of-the-windows) explains |
| `concealment_method` | `minimize_windows` | yes | how a window goes out of sight: `minimize_windows` minimizes it, and `hide_applications` hides its application once all the windows of the application go out of sight |
| `match_windows_by` | `title` | yes | how a switch pairs a record with an open window: `title` by the title and then the window id, and `id` by the window id, as [the section on switches](#a-switch-changes-only-the-windows-that-differ-from-the-record) explains |
| `missing_window_policy` | `match_title` | yes | whether a window of the same application with the same title takes the records of a recorded window that no longer exists, as the same section explains |
| `unmatched_window_action` | `open_new_window` | yes | what a switch does for a record in sight that no open window matches: `open_new_window` opens a new window of the same application, and `forget` opens none and drops the record from the profile, as the same section explains |
| `hidden_application_windows` | `leave_out` | yes | which windows of hidden applications the list of Control-Option and the search show |
| `list_layout` | `columns` | yes | how the list arranges the applications |
| `list_sizing` | `fill_screen` | yes | how the list uses the screen |
| `preview_method` | `blurred_snapshots` | yes | what the list shows beside a title: `blurred_snapshots` a blurred image of the window, or the icon for a window without an image, and `app_icons` the icon of the application |
| `preview_blur` | 1 | yes | how blurred a preview is: 1 keeps full detail, 2 half of it, 4 a quarter |
| `preview_size` | 0.1 by 0.1 | yes | the width and height of a preview, as fractions of the screen in front |
| `list_font_size` | 0.012 | yes | the size of the titles, as a fraction of the height of the screen in front |
| `title_overflow` | `wrap` | yes | what happens to a title longer than its space |
| `title_line_count` | 2 | yes | the most lines of a title under `wrap` |
| `url_event_name` | `desktop-manager` | no | the host of the URLs, as [the section on URLs](#a-url-reaches-every-action-of-the-desktop-manager) explains |
| `pause_after_login_seconds` | 300 | yes | the time after a login within which the first start of Hammerspoon pauses the active profile, and 0 turns the pause off, as [the section on the pause](#the-first-start-of-hammerspoon-soon-after-a-login-pauses-the-active-profile) explains |
| `timing` | | no | the waits and time limits of a switch, in seconds |

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

| Value of `hidden_application_windows` | The list of Control-Option and the search |
|---|---|
| `leave_out` | show no window of a hidden application, on any desktop |
| `list_where_found` | show a window of a hidden application while it stays a standard window, and while it lies on a desktop out of view, from the list of the window server |
| `list_all` | show every window of a hidden application, also a window that reports `AXDialog` or another subrole while its application is hidden, and the search adds such a window only for an application with a Dock icon |

Choosing a window of a hidden application in the list or the search unhides the application.
`leave_out` is the default because it costs the least memory and processor time.
Hammerspoon asks an application through accessibility whether it is hidden, so the desktop manager asks each application once, the first time that the list or the search needs the answer.
macOS then reports each hide and each unhide, so the later openings ask nothing.
When an application quits, the desktop manager forgets whether that application was hidden, and asks it again the next time that the list or the search needs the answer.
When macOS reports a quit without the bundle id and the name of the application, the desktop manager forgets the answers of every application.
Under `leave_out`, the list and the search skip every window of a hidden application, so accessibility reads none of them.
Fewer windows then show, and the list and the search take fewer previews.
Under `list_where_found`, the list and the search ask no application whether it is hidden.
Under `list_all`, the search also asks each running application with a Dock icon whether it is hidden, and each opening of the search asks accessibility for every window of each hidden one.
The section on the limits of macOS explains [why a window of a hidden application may report another subrole](#hammerspoon-and-macos-2701-limit-what-the-desktop-manager-can-do).
The setting changes the list and the search alone, and a switch, a capture or a removal of desktops treats the windows of hidden applications in the same way under every value.

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
| Profile 1 to Profile 9, with the name of a renamed profile after it, such as "Profile 2 · Writing" | activates the profile, or deactivates it while it is active, or restores its layout while it is paused |
| Reassign App Numbers | returns every number of the active profile, or of profile 0, to the default, as Control-Option-0 does |

The active profile shows a green dot, the label "Active profile" and the line "Active. Enter deactivates it.", and the other profiles show a white dot.
The paused profile shows a yellow dot, the label "Paused profile" and the line "Paused. Enter restores its layout.".
The extension reads `~/.hammerspoon/desktop-manager-state.json`, and draws the items again when the active profile, its pause or a name changes there.
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
| Activate profile N, or switch to it, or restore it while it is paused | Command-Option-Shift-N | `action=activate&profile=N` |
| Deactivate profile N while it is active | Command-Option-Shift-N while profile N is not paused | `action=deactivate&profile=N` |
| Deactivate the active profile | Command-Option-Shift-0 | `action=deactivate` |
| Activate profile N, or deactivate it while it is active, or restore it while it is paused | Command-Option-Shift-N | `action=toggle&profile=N` |
| Rename profile N | menu, Rename “Profile N”… while profile N is active | `action=rename&profile=N&name=Writing` |
| Change when monitor configurations are the same | Settings…, Same monitor configuration by | `action=cycle-monitor-matching` |
| Update the record of the active profile now, and end a pause | menu, Save layout of “Profile N” now | `action=save` |
| Give number N to a running application | menu, Application numbers | `action=number-app&number=N&app=Firefox` |
| Return number N to the default | menu, Application numbers | `action=release-app-number&number=N` |
| Return every number to the default | Control-Option-0 | `action=reset-app-numbers` |
| Clear the saved layouts of profile N, after a confirmation | Control-Option-Command-N, or menu, Clear a profile | `action=clear&profile=N` |
| Show the search of the windows | Control-Option-Command-Space | `action=search-windows` |
| Open the window of the settings | menu, Settings… | `action=open-settings` |

The numbers belong to the active profile, or to profile 0 while no profile is active.
In a terminal, `open -g "hammerspoon://desktop-manager?action=activate&profile=2"` activates profile 2.

## A switch changes only the windows that differ from the record

Activating a profile does the least work that brings back what the profile recorded.
A window goes to its place without a switch of desktops: to another desktop of its screen by a move by its window id, and to another screen by its frame, which macOS puts on the desktop that shows there.
The desktop manager sets a frame only while the window is on a desktop in view.

| The open window | The desktop manager |
|---|---|
| is where the profile recorded it, at the same frame | does nothing |
| is on its recorded desktop at another frame | sets the recorded frame, and moves the window by its id to the desktop in view first and back afterwards when its desktop does not show |
| is minimized, and the profile recorded it in sight | unminimizes it where it is, and then moves it as the next row says when macOS unminimized it onto another desktop |
| is in sight on another desktop of its recorded screen | moves it by its id to the recorded desktop |
| is on another screen than the recorded one | moves it by its id to the desktop in view when its desktop does not show, sets the recorded frame on the recorded screen, and then moves it by its id to the recorded desktop when another desktop shows there |
| is in sight, and the profile recorded it out of sight | minimizes it |
| is in sight, and another profile recorded it while this profile did not | minimizes it |
| was recorded by no profile, such as a window opened while no profile was active | minimizes it when the profile entered has a layout for the monitors, and otherwise leaves it, and the profile records it at its next update |

A window on another screen without a recorded frame stays where it is, and the alert after the switch and the console report it, as they report each window that stays away from its place.
While a screen shows a window in full screen, the restore after a change of monitors first shows the recorded desktop of that screen, or its desktop 1, so that no window joins the window in full screen.
A switch does the same when the profile has a layout for the monitors, or when the switch brings unseen windows into view.

Activating a profile with a layout for the monitors adds the desktops that the profile recorded and a screen lacks, in one opening of Mission Control, before the windows move.
After the windows are in place, the switch removes the desktops beyond the number of the profile, as [the section on the number of desktops of each screen](#a-profile-holds-the-number-of-desktops-of-each-screen-and-a-restore-removes-the-empty-desktops-beyond-it) says.
The switch also shows on each screen the desktop that it showed when the profile last recorded it, the screen of the focus last.
When the focus then lies on another screen, the switch gives the focus to the front window of the screen of the focus.
When that screen shows no window, the focus stays where the presses put it.
A screen whose recorded desktop shows already needs no press in Mission Control.

Hammerspoon can minimize a window or set its frame only after the window has shown once since Hammerspoon started, apart from the minimized windows and the windows of hidden applications.
Before a switch, and before the restore after a change of monitors, the desktop manager therefore brings the windows that Hammerspoon has not seen and that the switch acts on into view.
Each such window moves by its id to the desktop in view of its screen, where Hammerspoon reaches it.
The message at the top of every screen reads "Finding the windows on other desktops… please wait".
The switch then treats those windows as any other, so such a window shows on the desktop in view for a moment before it goes back or out of sight.
A window that accessibility still cannot reach in view goes back to its desktop by its id, and the alert after the switch names it.
The switch can minimize such a window or set its frame only once accessibility reaches it.
A window that the switch leaves where it is stays unseen, and a window that has shown once stays known until it closes.

`match_windows_by` chooses how a switch pairs each record with an open window.

| Value of `match_windows_by` | A record takes |
|---|---|
| `title`, the default | the open window of the same application with the same title, the one with the recorded window id first, and the window with the recorded window id when no title matches |
| `id` | the window with the recorded window id, and when that window no longer exists, what `missing_window_policy` chooses |

Under `title`, a window keeps its record when its application reopens it with a new window id, such as a window of Visual Studio Code after the application restarts, or when it moved to another desktop before Hammerspoon saw it.
A window whose title changed, such as a browser window on another tab, keeps its record through its window id, unless another window took the title.
A record with an empty title, such as the record of a window that macOS listed before Hammerspoon had the permission for Screen Recording, matches by its window id alone.

Under `id`, macOS gives a window that its application reopens a new window id, so `missing_window_policy` chooses which open window takes the record of a recorded window in sight that no longer exists.

| Value of `missing_window_policy` | The desktop manager |
|---|---|
| `match_title`, the default | takes an open window of the same application with the same title |
| `match_id_alone` | takes no other window |

`unmatched_window_action`, below, chooses whether a new window opens for a record that no window takes.
The values `match_title_or_open_new_window` and `open_new_window` of earlier versions still work as `match_title` and `match_id_alone`, and the console of Hammerspoon names the new value at each start.
A settings file of an earlier version that writes them as `missing_window_policy.MATCH_TITLE_OR_OPEN_NEW_WINDOW` and `missing_window_policy.OPEN_NEW_WINDOW` works in the same way.

Under the default, the desktop manager also treats an unrecorded window as the reopened copy of a closed recorded window of the same application with the same title.
Position and size play no part, because the desktop manager sets them on the window it takes, and because macOS opens a new window at the place of the last closed one.
A reopened window whose title changed, such as a browser window on another tab, counts as a new window.

`unmatched_window_action` chooses what a record in sight gets when no open window matches it, under either value of `match_windows_by`.

| Value of `unmatched_window_action` | The switch |
|---|---|
| `open_new_window`, the default | opens a new window of the same application, as the rest of this section says |
| `forget` | opens no window, and the profile drops the record at the update at the end of the switch, so the record does not come back at a later switch |

Under `forget`, the console of Hammerspoon names each window that the profile forgets.
A record out of sight that no window matches is dropped under both values.

The new window comes from the first of three sources that gives one:

1. A window that a launch of the application opened during the same switch, when the application was not running.
2. The menu item "New Window" of the application, or "New Finder Window" of the Finder.
3. A reopen of the application, as a click on its icon in the Dock sends, which shows the main window of an application such as Calendar.

The desktop manager leaves out Command-N, because Calendar, Mail, Notes and Slack create an event, a message or a note with it.
A new window opens on the desktop that shows, and the switch then sets its recorded frame and moves it to its recorded desktop, as for any other window.
The records of every profile then name the new window.
An application that opens no new window within ten seconds is reported in a notification.

The desktop manager saves the profiles, their records and their application numbers in `~/.hammerspoon/desktop-manager-state.json`.
A file that the desktop manager cannot read is moved aside to a name that ends in `.unreadable-` and the time, and the desktop manager starts a new state.
When the move fails, the notification and the console say so, and the next save replaces the unreadable file.

## Hammerspoon and macOS 27.0.1 limit what the desktop manager can do

The functions of Hammerspoon 1.1.1 that move a window to another desktop, or that switch, add or remove desktops, fail on macOS 27.0.1.
The issues [#3903](https://github.com/Hammerspoon/hammerspoon/issues/3903) and [#3897](https://github.com/Hammerspoon/hammerspoon/issues/3897) of Hammerspoon report the failures.
The desktop manager works around them as follows.

- macOS 27.0.1 unminimizes a window onto the desktop it was minimized on, also when another desktop shows, as the log of the desktop manager showed on 2026-10-10.
  A switch therefore brings minimized windows back without switching desktops.
  A window on another desktop of its screen moves there by its window id, through `hs.spaces.moveWindowToSpace` of [the build with pull request #3889](#a-build-of-hammerspoon-with-pull-request-3889-moves-windows-between-the-desktops-of-a-screen).
  A window moves to another screen when the desktop manager sets its frame there, because a move by id to another screen is untested.
  A frame set on a desktop out of view is untested as well, so a window out of view first comes into view by its id.
- A desktop shows through a press on its thumbnail in Mission Control, which the desktop manager finds through accessibility under the process WindowManager, as `hs.spaces.gotoSpace` of Hammerspoon 1.1.1 finds it under the Dock.
  The press reaches every desktop of every screen, and closes Mission Control.
  From 2026-10-17 to 2026-10-19, the console of Hammerspoon on macOS 27.0.1 showed presses that took 0.08 to 1.90 seconds until macOS reported the desktop and Mission Control had closed.
  On 2026-10-19, three presses had not shown their desktops with Mission Control closed after 2 seconds, and each desktop was inactive after the toggle that then closed Mission Control.
  The console does not show whether Mission Control was slow, ignored the press, or kept showing after the desktop had become active.
  The desktop manager therefore waits up to `desktop_show_timeout_seconds` of `timing`, 5 seconds by default, after the first press, for macOS to report the desktop and for Mission Control to close.
  When the desktop is still inactive `desktop_press_retry_seconds` of `timing` after the first press, 2 seconds by default, and Mission Control still shows, the desktop manager presses the thumbnail a second time.
  When Mission Control has closed by then and the desktop is still inactive, the desktop manager opens Mission Control a second time on the same display, presses the thumbnail again, and waits up to `desktop_show_timeout_seconds` from that press.
  The second press is the last, and no third opening follows.
  The press repeats in place of a toggle of Mission Control, because a toggle closes Mission Control toward the desktop that showed before, and so may undo a press that is still taking effect.
  Until the desktop is active, the desktop manager reads the desktops that macOS reports, and reads the accessibility tree of WindowManager only at the check for a second press, in the second opening and at the end of the wait.
  At the end of the wait, Mission Control closes by a toggle when it still shows, and the alert after the switch names a desktop that did not show.
  Check 3 of [the checks of the build](#four-commands-check-what-the-desktop-manager-assumes-of-the-build-and-of-macos-2701) tests the press by hand.
- On 2026-10-19, three presses of the list or the search went to a window of VS Code on the Dell monitor while Slack or iTerm2 on the built-in display was the frontmost application.
  Two of them failed, and the third showed its desktop after 3.17 seconds.
  In each of the three, the other window of VS Code had the focus of VS Code and lay on the desktop that the press replaced.
  In each of the two failures, the desktop of the press showed about one second after the press, when VS Code became active.
  The Dell monitor then showed the replaced desktop again, with that other window focused.
  The setting "When switching to an application, switch to a Space with open windows for the application" was on, and it fits this return to the replaced desktop.
  Five presses between the two windows while VS Code was the frontmost application showed their desktops.
  A press of the list or the search therefore first focuses the focused window of the application of the chosen window, or else its main window, when the following conditions hold.
  The application runs and is visible, while another application is the frontmost application.
  That window is a standard window other than the chosen one.
  That window lies on the desktop that shows on the screen of the desktop to show.
  No test on macOS 27.0.1 has confirmed yet that the focus of such a window keeps the desktops as they are.
  The desktop manager then waits up to `application_focus_timeout_seconds` of `timing`, 1 second by default, until the application is the frontmost application, and opens Mission Control also when it is not.
  The presses of a switch or a restore get no focus before the press.
- Adding a desktop presses the add button of Mission Control through accessibility, under the process WindowManager, which worked on 2026-10-10.
  Removing a desktop asks the desktop in the list of Mission Control to remove itself, as `hs.spaces.removeSpace` does, which no test on macOS 27.0.1 has confirmed yet.
  One opening of Mission Control holds the additions or the removals of every screen.
  When the button or the desktop is not found, the alert after the switch says so, and you add or remove the desktop in Mission Control.
- Accessibility reaches a window once its desktop has shown after Hammerspoon started, and it always reaches the minimized windows and the windows of hidden applications.
  The records, the search and the list of Control-Option find the other windows in the list of all windows of macOS, which `desktop_manager/macos/list_server_windows.js` prints through `osascript`.
  A switch moves those that it acts on into view by their ids first, as [the section on switches](#a-switch-changes-only-the-windows-that-differ-from-the-record) says.
  The desktop manager runs the script at the start, once a minute and when the search or the list of Control-Option opens, in about 0.2 seconds each time.
  It also runs the script before a switch, a restore or a removal of desktops acts on the list.
  At a change of desktop, the desktop manager records the desktop that each screen shows and the screen of the focus, and leaves the script and the windows alone.
- Hammerspoon follows the windows of the applications with a Dock icon and of the applications that a profile names, and leaves out the agents of the menu bar and the helpers without a Dock icon, such as MenuBarAgent or BetterDisplay.
  An application that gains a Dock icon is followed from the next time it comes to the front, and an application that Hammerspoon follows stays followed until it quits.
  Hammerspoon's window filter still asks every application that it follows for its windows after each change of desktop.
  Such a window counts when it lies on a desktop out of view, belongs to an application with a Dock icon, and measures at least 100 by 50 points, which leaves out most of the hidden windows that applications keep.
  An application may keep a window that it closed, such as a window of Tailscale or the "New Event" window of Calendar, and macOS lists such a window on its desktop while it shows nowhere.
  The script therefore also reads the tags and the attributes of each window through the private functions of SkyLight, and a window counts only when yabai would list it on its desktop by the same values.
  A window of a hidden application follows the same rule, and on 2026-10-17 the window server marked a window of the hidden Activity Monitor as yabai would list it.
  Its title needs the permission for Screen Recording, and without it the window shows as "untitled window".
  Choosing such a window in the list or the search shows its desktop through Mission Control, and the desktop manager then waits up to `window_reach_timeout_seconds` of `timing`, 1 second by default, for accessibility to reach it.
  The message at the top of every screen stays during the wait.
- The window filter of Hammerspoon drops a window whose subrole changes while its application is hidden, as the windows of Calendar and of Activity Monitor do, which report `AXDialog` then.
  A switch looks the recorded windows up among all windows of macOS.
  Under the setting `hidden_application_windows` `list_where_found`, the list of Control-Option and the search take only standard windows.
  The list and the search therefore leave out such a window while its desktop shows, and list it from the window server while its desktop is out of view.
  Under `list_all`, they take the window whatever its subrole, and under the default `leave_out` they show no window of a hidden application, as [the section on the settings](#settings-of-the-desktop-manager-live-in-desktop_managerdefault_settingslua) explains.

### The previews of the list need the permission for Screen Recording

The previews in the list and the search come after the list or the panel shows, and need the permission for Screen Recording.
A helper process, `desktop_manager/macos/capture_window_previews.js`, takes them with an old screen capture function of macOS.
On 2026-10-10, on macOS 27.0.1, that function blocked Hammerspoon for two minutes with every shortcut unresponsive, and took less than 0.3 seconds after the permission was turned on.
Hammerspoon starts the helper through `osascript`, so the helper has the permission for Screen Recording of Hammerspoon, and a capture blocks the helper alone.
The helper captures a window at the resolution of its points, which has a quarter of the pixels on a Retina display, and captures a window smaller than its preview at full resolution.
Hammerspoon shows each preview as the helper gives it, so a key waits for no capture.
When the helper reports an image whose capture took longer than half a second, Hammerspoon stops the helper, and the previews stop until the next reload, because a slow image may start a block such as the one of 2026-10-10.
A helper that gives no output for one and a half seconds, or that fails, stops as well, and the windows that wait for a preview keep their icons until the list or the search opens again.
The console says why the helper stopped.
On a machine where Hammerspoon lacks the permission, choose `app_icons`, or time one image first.

1. In System Settings, Privacy & Security, Screen & System Audio Recording, turn on Hammerspoon.
2. In a terminal, run the command below, which may itself block Hammerspoon for minutes when the function blocks.

```sh
hs -c 'local started = hs.timer.secondsSinceEpoch(); local image = hs.window.snapshotForID(hs.window.focusedWindow():id()); return tostring(image ~= nil) .. " after " .. (hs.timer.secondsSinceEpoch() - started) .. " seconds"'
```

The previews work when the command prints `true` after less than half a second.

### The desktop manager uses one pull request of Hammerspoon and waits for three more

On 2026-10-13, four open pull requests of Hammerspoon would lift some of these limits once a release of Hammerspoon holds them.
None of them is in Hammerspoon 1.1.1, the latest release, of 2026-02-26.
The desktop manager uses #3889 through a build of its branch, as the next section says.

| Pull request | What it changes in Hammerspoon | What the desktop manager gains |
|---|---|---|
| [#3889](https://github.com/Hammerspoon/hammerspoon/pull/3889) | `hs.spaces.moveWindowToSpace` moves a window by its id through a private function of macOS, which the author tested on macOS 26.5 and a user reported working on macOS 27.0.1 | a move of any window to any desktop of its screen, also a window that Hammerspoon has not seen, without showing its desktop first, in use through the build |
| [#3904](https://github.com/Hammerspoon/hammerspoon/pull/3904) | `hs.spaces` finds Mission Control under the process WindowManager of macOS 27 | `hs.spaces.gotoSpace`, `addSpaceToScreen` and `removeSpace` instead of the own module of Mission Control |
| [#3859](https://github.com/Hammerspoon/hammerspoon/pull/3859) and [#3866](https://github.com/Hammerspoon/hammerspoon/pull/3866) | `hs.eventtap.event` writes the fields of an event as floating-point numbers | desktop switches through the swipe events of the Dock, in about 40 milliseconds, without the slide and without Mission Control in sight |

### A build of Hammerspoon with pull request #3889 moves windows between the desktops of a screen

The desktop manager calls `hs.spaces.moveWindowToSpace` for each window that goes to another desktop of its screen.
Such a window is on another desktop of its recorded screen, or macOS unminimized it onto another desktop, or it needs its frame while it is out of view, or Hammerspoon has not seen it.
The desktop manager waits up to `window_move_timeout_seconds` of `timing`, 1 second by default, for each window from its own call, and each window that does not arrive shows in the alert after the switch.
Hammerspoon 1.1.1 returns true on macOS 27 and leaves the window where it is, so the desktop manager needs the build.

On 2026-10-17, the branch of the pull request, `fix-move-window-to-space-tahoe` of `franzbu/hammerspoon` at `8cde946`, built with Xcode 27.1 once two checks of Hammerspoon that Xcode 27 makes fail were turned off on the command line:

```sh
git clone --depth 1 --branch fix-move-window-to-space-tahoe https://github.com/franzbu/hammerspoon.git
cd hammerspoon
xcodebuild -workspace Hammerspoon.xcworkspace -scheme Release -configuration Release \
  -destination platform=macOS -derivedDataPath ../derived-data build \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual \
  GCC_TREAT_WARNINGS_AS_ERRORS=NO 'OTHER_CFLAGS=$(inherited) -Wno-quoted-include-in-framework-header'
```

The app is `../derived-data/Build/Products/Release/Hammerspoon.app`, signed for this Mac alone, and its version is the commit instead of a number.
The clone and `../derived-data` may be deleted once the app is in place.
The build has the identifier `org.hammerspoon.Hammerspoon` of Hammerspoon 1.1.1, so macOS keeps one Accessibility entry for both.
On 2026-10-17, with both apps installed, the build lost its permission each time it started, also after the entry was removed and added again.
The build therefore replaces 1.1.1 in `/Applications`.

1. Run `brew uninstall --cask hammerspoon`, without `--zap`, which would move `~/.hammerspoon` to the Trash.
   The uninstall quits Hammerspoon and removes `/Applications/Hammerspoon.app` and the command `hs`.
2. Move the built app to `/Applications/Hammerspoon.app`, and run `ln -s /Applications/Hammerspoon.app/Contents/Frameworks/hs/hs /opt/homebrew/bin/hs`.
3. Run `tccutil reset Accessibility org.hammerspoon.Hammerspoon`, and open `/Applications/Hammerspoon.app`.
4. When Hammerspoon asks, turn it on in System Settings, Privacy & Security, Accessibility, and do the same under Screen & System Audio Recording when the previews are used.
5. Quit Hammerspoon and open it once more, so that it starts with the permission.
6. In the preferences of Hammerspoon, turn off the check for updates, so that the build does not offer 1.1.1 as an update.

The first line of the diagnostics then names the version of the build, the commit instead of a number.
The command `hs` of the build writes a file of profile data, `default.profraw`, into the current folder each time it ends.
To keep the file away, run the command as `LLVM_PROFILE_FILE=/dev/null hs -c '…'`, or export that variable in the profile of the shell.
The four checks at the end of this section show whether the build and macOS 27.0.1 do what the desktop manager assumes.
To go back, quit Hammerspoon, delete `/Applications/Hammerspoon.app` and `/opt/homebrew/bin/hs`, run `brew install --cask hammerspoon`, and do steps 3 to 5 again.
Hammerspoon 1.1.1 then leaves every window that the desktop manager moves by its id where it is.

#### Four commands check what the desktop manager assumes of the build and of macOS 27.0.1

Each command below checks one of four facts that the desktop manager rests on.
The console of Hammerspoon has shown the press of check 3 at work, as [the section on the limits of macOS](#hammerspoon-and-macos-2701-limit-what-the-desktop-manager-can-do) says.
No test on macOS 27.0.1 has confirmed the facts of checks 1, 2 and 4, or the message above Mission Control and the move of the focus that check 3 also checks.
Run each command in a terminal while Hammerspoon runs the desktop manager and no profile is active.
Each command starts its work with timers, waits, and prints the table `T` with a second `hs -c`.
Each command keeps its timers in `T`, because Hammerspoon stops a timer that Lua collects.
A field missing from `T` means that the check did not finish, and the command can run again.

Check 1 shows whether the build moves a window of another application to another desktop of its screen by its id.
Before the command, open a TextEdit window on a screen with at least two desktops.
The window leaves for another desktop for one second and comes back.

```sh
hs -c 'T = {}; local app = hs.application.get("TextEdit"); local w = app and app:mainWindow(); if not w then return "no TextEdit window" end; T.id = w:id(); local s = w:screen(); T.from = hs.spaces.windowSpaces(T.id)[1]; for _, sp in ipairs(hs.spaces.spacesForScreen(s)) do if not T.to and sp ~= T.from and hs.spaces.spaceType(sp) == "user" then T.to = sp end end; T.called = hs.spaces.moveWindowToSpace(T.id, T.to); T.timer = hs.timer.doAfter(1, function() T.after_move = hs.spaces.windowSpaces(T.id)[1]; hs.spaces.moveWindowToSpace(T.id, T.from); T.timer2 = hs.timer.doAfter(1, function() T.after_back = hs.spaces.windowSpaces(T.id)[1] end) end); return "moving the TextEdit window to desktop " .. tostring(T.to)' && sleep 3 && hs -c 'return hs.inspect(T)'
```

The fact holds when `after_move` equals `to` and `after_back` equals `from`.

Check 2 shows whether the build moves a window that Hammerspoon has not seen into view, where accessibility reaches it.
Before the command, put a TextEdit window on desktop 2 of the main screen, show desktop 1, quit Hammerspoon, open it again, and leave desktop 2 unvisited.

```sh
hs -c 'T = {}; local s = hs.screen.mainScreen(); T.active = hs.spaces.activeSpaceOnScreen(s); for _, info in ipairs(hs.window.list(true)) do if not T.id and info.kCGWindowOwnerName == "TextEdit" and info.kCGWindowLayer == 0 and hs.window.get(info.kCGWindowNumber) == nil then T.id = info.kCGWindowNumber end end; if not T.id then return "no TextEdit window that Hammerspoon has not seen" end; T.from = hs.spaces.windowSpaces(T.id)[1]; T.called = hs.spaces.moveWindowToSpace(T.id, T.active); T.timer = hs.timer.doAfter(1.5, function() T.now = hs.spaces.windowSpaces(T.id)[1]; local w = hs.window.get(T.id); T.reached = w ~= nil; T.title = w and w:title() end); return "moving window " .. T.id' && sleep 2.5 && hs -c 'return hs.inspect(T)'
```

The fact holds when `now` equals `active` and `reached` is true.
The TextEdit window then stays on desktop 1.

Check 3 shows whether a press on a thumbnail in Mission Control under WindowManager shows the desktop, and whether a message shows above Mission Control.
Before the command, have at least two desktops on the main screen and show desktop 1.
The command shows two labels at the top of the main screen, "level overlay" and "level screenSaver", opens Mission Control one second later, and presses the thumbnail of desktop 2.
Note which labels stay visible while Mission Control shows.
When Mission Control stays open, press Escape.

```sh
hs -c 'T = {}; local s = hs.screen.mainScreen(); local f = s:frame(); T.screen = s:id(); T.before = hs.spaces.activeSpaceOnScreen(s); T.target = hs.spaces.spacesForScreen(s)[2]; T.canvases = {}; for i, level in ipairs({"overlay", "screenSaver"}) do local c = hs.canvas.new({x = f.x + 40 + (i - 1) * 280, y = f.y + 12, w = 260, h = 40}); c:level(hs.canvas.windowLevels[level]); c:behaviorAsLabels({"canJoinAllSpaces", "stationary"}); c:replaceElements({type = "rectangle", action = "fill", fillColor = {white = 0.12, alpha = 0.92}}, {type = "text", text = "level " .. level, textColor = {white = 1, alpha = 1}, textSize = 16, frame = {x = 12, y = 9, w = 236, h = 24}}); c:show(); T.canvases[i] = c end; local function find(e, wanted, depth) if depth == 0 then return nil end for _, child in ipairs(e:attributeValue("AXChildren") or {}) do if wanted(child) then return child end local found = find(child, wanted, depth - 1) if found then return found end end end; T.timer = hs.timer.doAfter(1, function() hs.spaces.toggleMissionControl(); T.timer2 = hs.timer.doAfter(1.5, function() local wm = hs.application.applicationsForBundleID("com.apple.WindowManager")[1]; local group = wm and find(hs.axuielement.applicationElement(wm), function(e) return e:attributeValue("AXIdentifier") == "mc.display" and e:attributeValue("AXDisplayID") == T.screen end, 6); local list = group and find(group, function(e) return e:attributeValue("AXIdentifier") == "mc.spaces.list" end, 4); local thumbnail = list and (list:attributeValue("AXChildren") or {})[2]; T.found = {group = group ~= nil, list = list ~= nil, thumbnail = thumbnail ~= nil}; T.pressed = thumbnail and tostring(thumbnail:performAction("AXPress")) or "no thumbnail"; T.timer3 = hs.timer.doAfter(2, function() T.after = hs.spaces.activeSpaceOnScreen(s); T.focused_after = hs.spaces.focusedSpace(); T.shown = T.after == T.target; for _, c in ipairs(T.canvases) do c:delete() end; T.canvases = nil end) end) end); return "pressing desktop 2 in Mission Control in about 2.5 seconds"' && sleep 6 && hs -c 'return hs.inspect(T)'
```

The fact holds when `shown` is true, which means that the main screen shows desktop 2 after the press.
On a Mac with a second screen, give the focus to a window on the second screen before the command.
`focused_after` then equals `after` when the press moves the focus to the main screen, as the fake of the tests assumes.
The message of the desktop manager has the level `overlay`, so it shows above Mission Control when the label "level overlay" stayed visible.

Check 4 shows whether the desktop manager removes a desktop through Mission Control under WindowManager, and where macOS puts a minimized window of the removed desktop.
Before the command, add a last desktop to the main screen, put a TextEdit window there and minimize it, and show desktop 1.
The command removes the last desktop through the module of the desktop manager, and unminimizes the window once the removal has ended.

```sh
hs -c 'T = {}; local desktops = require("desktop_manager.macos.mission_control_desktops"); local s = hs.screen.mainScreen(); local spaces = hs.spaces.spacesForScreen(s); T.last = spaces[#spaces]; T.count_before = #spaces; local app = hs.application.get("TextEdit"); for _, w in ipairs(app and app:allWindows() or {}) do if not T.id and w:isMinimized() then T.id = w:id() end end; if not T.id then return "no minimized TextEdit window" end; T.desktop_before = hs.spaces.windowSpaces(T.id)[1]; T.listed_before = false; for _, id in ipairs(hs.spaces.windowsForSpace(T.last) or {}) do if id == T.id then T.listed_before = true end end; desktops.edit({{screen_uuid = s:getUUID(), slot_key = "the main screen", desktops_to_add = 0, space_ids_to_remove = {T.last}}}, function() return false end, desktop_manager.settings.timing, function(failures) T.failures = failures; T.count_after = #hs.spaces.spacesForScreen(s); T.desktop_after = hs.spaces.windowSpaces(T.id)[1]; local w = hs.window.get(T.id); T.minimized_after = w and w:isMinimized(); if w then w:unminimize() end; T.timer = hs.timer.doAfter(1, function() T.desktop_unminimized = hs.spaces.windowSpaces(T.id)[1]; T.active = hs.spaces.activeSpaceOnScreen(s) end) end); return "removing desktop " .. T.last' && sleep 7 && hs -c 'return hs.inspect(T)'
```

The removal works when `failures` is empty and `count_after` is one less than `count_before`.
The rule that a minimized window keeps no desktop holds when `minimized_after` is true and `desktop_after` names a desktop of the main screen.
`listed_before` tells whether macOS lists a minimized window on its desktop, which the check right before each removal uses for the windows of the applications that the desktop manager leaves to macOS.
`desktop_after` names the desktop where macOS put the minimized window, and `desktop_unminimized` the desktop where it showed the window again, beside `active`, the desktop that the main screen shows.

## Diagnostics in the Hammerspoon console show what the desktop manager reads

`hs -c "desktop_manager:print_diagnostics()"` prints what the desktop manager reads of the screens, desktops and windows, and which profiles recorded each window, and changes nothing.
"Print diagnostics to the console" in the menu bar item prints the same into the Hammerspoon console.
The diagnostics start with the version of Hammerspoon, and give the desktop that each screen shows and the numbers of desktops that the desktop manager tracks.
They also give the number of desktops and the desktop shown of each screen in the record of the active profile.
The diagnostics also give whether the active profile is paused, and whether it leaves the monitor configuration to macOS.
Each switch writes its plan and its duration to the console.
Each opening of Mission Control also writes how long it waited for the release of the modifiers and until Mission Control showed.
The log line of each press on a thumbnail names the window that it focused before the press and when its application became the frontmost application, or says that it focused none.
The same line gives the seconds until macOS reported the desktop and until Mission Control closed, and when a second press or a second opening followed.
A press that focused a window and then could not open Mission Control or press the thumbnail writes the focus and the failure.
A press whose desktop did not show by the end of the wait also writes a warning with the desktop that its screen shows, whether Mission Control still showed, and the error of the second press.
A press whose second opening failed gives the failure at the end of its log line instead.
The rest of a switch is the animation of macOS, which "Reduce motion" in step 6 of the installation shortens.

Each opening of the search writes one line to the console when the panel closes.
The line gives the seconds until the panel showed, until the first and the last preview, and until the new list of the window server.
The line also gives how long the previews and the new list blocked Hammerspoon, and the number of keys with the longest wait of a key before the search took it.

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
The extension of the window tiling takes `url_event_name` from `asyar-window-tiling/src/settings.generated.json`, which a generator writes from this file, so a change of `url_event_name` also needs `make asyar-window-tiling-settings` and a new build of the extension, as [the section on the code](#the-code-of-each-tool-splits-into-a-tested-core-and-a-macos-layer) says.

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

Each item runs one AppleScript through `/usr/bin/osascript`, which counts, asks, erases and reports by itself, because Asyar gives the output of a program to no background command.
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
| `keyboard_shortcuts/core/` | the registry of the shortcuts of every tool, with the defaults, the overrides and the shortcuts left out, the shortcuts of macOS that a shortcut collides with, and the content of the window "Keyboard shortcuts…" |
| `keyboard_shortcuts/macos/` | the center that binds the shortcuts and saves the overrides, the reading and turning off of macOS shortcuts, the window "Keyboard shortcuts…", and the frame of the web windows of both tools |
| `desktop_manager/core/` | the decisions of the desktop manager: the checks of the settings, the settings that the window "Settings…" changes, the actions with their default shortcuts, monitor configurations, the desktops of each screen, window matching, profile records, the pool of managed applications, plans for concealing, restoring and opening missing windows, the way of each window to its place, the numbers of desktops and their removal, application numbers and the view of their list, the search of the windows and its scores, the pacing of the previews, the output of the helper of the previews, the windows of macOS that accessibility does not reach and the ones to bring into view, the text of the log of a press in Mission Control, the text of the console line of an opening of the search, the pause of the active profile after a login, URL commands, and the closed sets of the settings |
| `desktop_manager/macos/` | the calls of the desktop manager to Hammerspoon: reading screens, desktops and windows, the windows that Hammerspoon knows, the list of all windows of macOS and its script, the helper script that takes the previews, showing, adding and removing desktops through Mission Control, bringing windows into view and moving them by their ids, opening new windows, the watchdog of a switch, switching to the application of a number, the list of the numbered applications and the panel of the search with the elements they share, the windows of hidden applications in them, the menu bar item, the message during a switch, the window of the managed applications, the window of the settings, the diagnostics and the controller |
| `window_tiling/core/` | the positions of the window tiling and the frame of each position on a screen |
| `window_tiling/macos/` | the controller of the window tiling, which hands its actions to the center of the shortcuts, binds its URLs and sets the frame of the focused window |
| `tests/` | unit tests of the cores, and tests of the flows of the desktop manager, one file per subject, and of the tiling controller against `tests/fake_hammerspoon.lua`, with the world of the controller in `tests/controller_world.lua` and the fixtures that several files share in `tests/fake_worlds.lua` |
| `tools/` | the generators of the launcher scripts and of the settings of the Asyar extensions of the desktop manager and of the window tiling, the script that turns one shortcut of macOS off, and the script that removes one rule of the code at a time to find the rules that no test checks |
| `type_definitions/` | the signatures of the functions of Hammerspoon that the code calls with arguments that `tests/fake_hammerspoon.lua` leaves out, which lua-language-server reads in place of the functions of the fake, and which nothing loads at run time |
| `launcher-scripts/` | the scripts for Asyar and Raycast, written by the generator |
| `asyar-extension/` | the Asyar extension of the desktop manager, in TypeScript, with its manifest, its worker, its generated settings and the unit tests of its items and its worker |
| `asyar-window-tiling/` | the Asyar extension of the window tiling, in TypeScript, with its manifest, its worker, its generated settings and the unit tests of its URL and its worker |
| `asyar-trash/` | the Asyar extension that opens and empties the Trash, in TypeScript, with its manifest, its worker and the unit tests of its scripts |

The two tools share the modules of `keyboard_shortcuts/` alone.
The modules of `desktop_manager/core/`, `window_tiling/core/` and `keyboard_shortcuts/core/` call no Hammerspoon function, so `lua` 5.4 runs their tests outside Hammerspoon.
The fake of Hammerspoon unminimizes a window onto its own desktop, as macOS 27.0.1 does, presses the thumbnails of Mission Control, and moves windows by their ids.
A press of the fake moves the focus to the display of its thumbnail, which check 3 tests, and a test can turn that move off.
A test can turn on the return to the replaced desktop after a press from another application, as [the section on the limits of Hammerspoon and macOS 27.0.1](#hammerspoon-and-macos-2701-limit-what-the-desktop-manager-can-do) describes it.
The tests check the logic of the tools, and say nothing about the behaviour of macOS.

`make check` checks the syntax with `luac -p`, and the syntax of the two scripts of JavaScript for Automation in `desktop_manager/macos/` with `node --check`.
It also lints with `luacheck`, checks the formatting with `stylua --check`, runs the tests, and compares the generated files with their generators.
`make check` also runs `make type-check`, which checks the annotations with `lua-language-server --check . --checklevel=Warning` in about 6 seconds and fails on any warning.
A warning that only a slower or less correct code would remove stays, with a `---@diagnostic disable-next-line: <code>` annotation and a comment beside it that gives the reason.
`make format` formats the code with `stylua`.
The programs of these commands come from Homebrew: `lua@5.4`, `luacheck`, `stylua`, `node` and `lua-language-server`.

`make check-asyar-extension` checks the types of the extension of the desktop manager, runs its unit tests, runs `asyar validate` of the SDK of Asyar, and builds it.
`make check-asyar-window-tiling` does the same for the extension of the window tiling, and `make check-asyar-trash` for the extension of the Trash.
After a change to an extension, run its `make link-...` target again, or `npm run build` in its folder, because Asyar loads the built files through the link.

Two generators take the numbers of profiles and of applications, and the host of the URLs, `url_event_name`, from `desktop_manager/default_settings.lua`.
`make launcher-scripts` runs `tools/write_launcher_scripts.lua`, which writes the scripts.
`make asyar-extension-settings` runs `tools/write_asyar_extension_settings.lua`, which writes `asyar-extension/src/settings.generated.json`.
A third generator takes `url_event_name` from `window_tiling/default_settings.lua`.
`make asyar-window-tiling-settings` runs `tools/write_asyar_window_tiling_settings.lua`, which writes `asyar-window-tiling/src/settings.generated.json`.
Run them after a change of the settings, because `make check` fails when a generated file differs from the output of its generator.

`lua tools/remove_rules_one_at_a_time.lua <rules file> [word ...]` checks the tests against the rules of the code.
A rules file is a Lua file that returns a list of rules, and a rule is a `name` with a list of `edits` that turn the code into a version without the rule.
Each edit holds a `path` relative to the repository, the `old` text, which must occur exactly once in that file, and the `new` text:

```lua
return {
    {
        name = "the poll waits 0.2 seconds",
        edits = {
            {
                path = "desktop_manager/macos/track_windows.lua",
                old = "local REACH_POLL_SECONDS = 0.2",
                new = "local REACH_POLL_SECONDS = 0.05",
            },
        },
    },
}
```

The script applies each rule to its own copy of the tree under a temporary folder, runs the tests there, and prints the tests that fail.
The script leaves the repository unchanged, and with words it runs only the rules whose names hold one of them.
The script exits with status 1 in each of four cases:

- A rule fails no test.
- The file of an edit is missing, or its `old` text occurs more or less than once.
- The tests of a rule do not run.
- The unmodified copy fails a test.

`make check` leaves the script out, because the script runs the whole test suite once for each rule.

The code follows the [LuaRocks style guide](https://github.com/luarocks/lua-style-guide), read on 2026-10-10, with four departures.

- Indentation is four spaces, as in the Lua extensions that Hammerspoon 1.1.1 ships, where the guide uses three.
- Types are written as annotations of lua-language-server, such as `---@param`, where the guide uses LDoc, because the language server checks them.
- Misuse of a function raises `error` with a message that states the fact and the value, where the guide uses `assert`.
- `init.lua` sets one global per tool, `desktop_manager` and `window_tiler`, because Hammerspoon stops the hotkeys and watchers that Lua garbage-collects, and because the command-line tool `hs` reaches the controllers through them.

Lines are at most 100 characters long, as `stylua.toml` and `.luacheckrc` set.
