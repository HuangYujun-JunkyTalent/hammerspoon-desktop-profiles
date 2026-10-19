local macos_shortcut_settings = require("keyboard_shortcuts.macos.macos_shortcut_settings")
local shortcut_registry = require("keyboard_shortcuts.core.shortcut_registry")

---The window that lists the shortcuts of every utility and changes them.
---Clicking a shortcut records the next key press with modifiers, while every shortcut of the tools
---is off, so that pressing a shortcut of the tools records it instead of running it.
---A recorded shortcut that another action or macOS uses waits for a choice: move it from the other
---action, turn the macOS shortcut off, use it anyway, or cancel.
local shortcut_window = {}

local MESSAGE_HANDLER = "shortcuts"
local WINDOW_SIZE = { w = 720, h = 720 }

---A recorded shortcut that waits for the choice of the user.
---@class PendingShortcut
---@field id string the action that would take the shortcut
---@field shortcut Shortcut
---@field holder table|nil the id and the title of the other action that has the shortcut
---@field macos MacosShortcut|nil the shortcut of macOS that is on with the same keys

---@class ShortcutWindowModel
---@field groups table[] each with a name and rows, a row being a ShortcutRow with the macOS
---shortcut that it collides with
---@field problems string[]
---@field pending table|nil the PendingShortcut, without the details of the macOS shortcut

---@class ShortcutWindow
---@field view table the hs.webview
---@field center ShortcutCenter
---@field problems string[] the problems of the last change, shown above the list
---@field pending PendingShortcut|nil
---@field model ShortcutWindowModel the content that the page shows now
---@field on_closed fun()

---@param shortcut MacosShortcut|nil
---@return table|nil the part of the shortcut of macOS that the page shows
local function describe_macos(shortcut)
    return shortcut and { id = shortcut.id, name = shortcut.name } or nil
end

---@param center ShortcutCenter
---@param problems string[]
---@param pending PendingShortcut|nil
---@param find_macos_conflict fun(shortcut: Shortcut): MacosShortcut|nil
---@return ShortcutWindowModel
function shortcut_window.build_model(center, problems, pending, find_macos_conflict)
    local groups, group_by_name = {}, {}
    for _, row in ipairs(center:list_rows()) do
        local group = group_by_name[row.group]
        if not group then
            group = { name = row.group, rows = {} }
            group_by_name[row.group] = group
            table.insert(groups, group)
        end
        table.insert(group.rows, {
            id = row.id,
            title = row.title,
            shortcut = row.shortcut,
            default = row.default,
            default_text = row.default and shortcut_registry.describe(row.default) or "none",
            is_default = row.is_default,
            macos_conflict = row.shortcut and describe_macos(find_macos_conflict(row.shortcut)),
        })
    end
    local pending_view = nil
    if pending then
        pending_view = {
            id = pending.id,
            shortcut = pending.shortcut,
            text = shortcut_registry.describe(pending.shortcut),
            holder = pending.holder,
            macos = describe_macos(pending.macos),
        }
    end
    return { groups = groups, problems = problems, pending = pending_view }
end

local STYLE = [[
:root { color-scheme: light dark; --accent: #0a84ff; --warn: #c27c0e;
  --card: rgba(127, 127, 127, 0.08); --line: rgba(127, 127, 127, 0.18);
  font: 13px -apple-system, BlinkMacSystemFont, sans-serif; }
body { margin: 0; }
header { position: sticky; top: 0; z-index: 2; padding: 16px 20px 10px; background: Canvas;
  border-bottom: 1px solid var(--line); }
h1 { font-size: 17px; margin: 0 0 4px; }
.lead { margin: 0 0 10px; color: GrayText; }
#filter { width: 100%; box-sizing: border-box; font-size: 13px; padding: 6px 10px;
  border-radius: 7px; border: 1px solid var(--line); background: var(--card); }
main { padding: 6px 20px 70px; }
h2 { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: GrayText;
  margin: 18px 0 6px 4px; }
.card { background: var(--card); border-radius: 10px; overflow: hidden; }
.row { display: flex; align-items: center; gap: 10px; padding: 8px 12px;
  border-top: 1px solid var(--line); }
.row:first-child { border-top: none; }
.title { flex: 1; }
.changed { display: inline-block; width: 6px; height: 6px; border-radius: 3px;
  background: var(--accent); margin-left: 6px; vertical-align: middle; }
.keys { min-width: 150px; text-align: center; padding: 4px 8px; border-radius: 7px;
  border: 1px solid var(--line); background: Canvas; cursor: pointer; font: inherit; }
.keys:hover { border-color: var(--accent); }
.keys.none { color: GrayText; }
.keys.recording { border-color: var(--accent); color: var(--accent);
  box-shadow: 0 0 0 3px rgba(10, 132, 255, 0.25); }
kbd { display: inline-block; min-width: 18px; padding: 1px 5px; margin: 0 1px;
  border-radius: 5px; border: 1px solid var(--line); border-bottom-width: 2px;
  font: 12px -apple-system, sans-serif; background: var(--card); }
.icon { border: none; background: none; cursor: pointer; font-size: 14px; color: GrayText;
  width: 24px; padding: 2px; border-radius: 5px; }
.icon:hover { background: var(--card); color: CanvasText; }
.icon[hidden] { visibility: hidden; display: inline-block; }
.note { margin: 0 12px 10px; padding: 8px 10px; border-radius: 8px; font-size: 12px; }
.note.warn { background: rgba(194, 124, 14, 0.13); }
.note .choices { margin-top: 6px; display: flex; gap: 6px; flex-wrap: wrap; }
.note button, footer button { font: inherit; padding: 3px 12px; border-radius: 6px;
  border: 1px solid var(--line); background: Canvas; cursor: pointer; }
.note button.primary, footer button.primary { background: var(--accent); color: white;
  border-color: var(--accent); }
.banner { margin: 10px 0 0; padding: 8px 10px; border-radius: 8px;
  background: rgba(208, 54, 45, 0.13); }
.empty { color: GrayText; padding: 12px; }
footer { position: fixed; bottom: 0; left: 0; right: 0; display: flex;
  justify-content: space-between; align-items: center; padding: 10px 20px; background: Canvas;
  border-top: 1px solid var(--line); }
footer .hint { color: GrayText; font-size: 11px; }
]]

local SCRIPT = [[
const post = (body) => window.webkit.messageHandlers.shortcuts.postMessage(body);
const SYMBOLS = { ctrl: "⌃", alt: "⌥", shift: "⇧", cmd: "⌘", fn: "fn" };
const ORDER = ["ctrl", "alt", "shift", "cmd", "fn"];
const KEY_SYMBOLS = { "return": "↩", padenter: "⌤", space: "Space", tab: "⇥", delete: "⌫",
  forwarddelete: "⌦", escape: "⎋", left: "←", right: "→", up: "↑", down: "↓", home: "↖",
  end: "↘", pageup: "⇞", pagedown: "⇟" };
const NAMED = { Enter: "return", NumpadEnter: "padenter", Space: "space", Tab: "tab",
  Backspace: "delete", Delete: "forwarddelete", Escape: "escape", Home: "home", End: "end",
  PageUp: "pageup", PageDown: "pagedown", ArrowLeft: "left", ArrowRight: "right",
  ArrowUp: "up", ArrowDown: "down", Minus: "-", Equal: "=", BracketLeft: "[",
  BracketRight: "]", Backslash: "\\", Semicolon: ";", Quote: "'", Comma: ",", Period: ".",
  Slash: "/", Backquote: "`" };
const keyName = (code) => {
  let match = code.match(/^Key([A-Z])$/) || code.match(/^Digit(\d)$/);
  if (match) return match[1].toLowerCase();
  match = code.match(/^F(\d+)$/);
  if (match) return "f" + match[1];
  return NAMED[code];
};
const escapeHtml = (text) => String(text).replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const keycaps = (shortcut) => {
  if (!shortcut) return "None";
  const held = new Set(shortcut.modifiers || []);
  const parts = ORDER.filter((m) => held.has(m)).map((m) => SYMBOLS[m]);
  const key = KEY_SYMBOLS[shortcut.key] || shortcut.key.toUpperCase();
  return parts.concat([key]).map((part) => "<kbd>" + escapeHtml(part) + "</kbd>").join("");
};
let model = null;
let recordingId = null;
const pendingNote = (pending) => {
  const keys = keycaps(pending.shortcut);
  const parts = [];
  if (pending.holder) parts.push(keys + " is the shortcut of “"
    + escapeHtml(pending.holder.title) + "”.");
  if (pending.macos) parts.push("macOS uses " + keys + " for “"
    + escapeHtml(pending.macos.name) + "”, and macOS may take the keys first.");
  const choices = [];
  if (pending.holder && pending.macos) {
    choices.push(["primary", "Move it here and turn off the macOS shortcut",
      { remove_holder: true, turn_off_macos: true }]);
    choices.push(["", "Move it here only", { remove_holder: true }]);
  } else if (pending.holder) {
    choices.push(["primary", "Move it here", { remove_holder: true }]);
  } else if (pending.macos) {
    choices.push(["primary", "Turn off the macOS shortcut and use it here",
      { turn_off_macos: true }]);
    choices.push(["", "Use it anyway", {}]);
  }
  choices.push(["", "Cancel", { cancel: true }]);
  const buttons = choices.map(([cls, label, choice], index) =>
    "<button class='" + cls + "' data-choice='" + index + "'>" + escapeHtml(label) + "</button>");
  return { html: "<div class='note warn'>" + parts.join(" ") + "<div class='choices'>"
    + buttons.join("") + "</div></div>", choices: choices.map((c) => c[2]) };
};
const render = (next) => {
  model = next;
  const filter = document.getElementById("filter").value.trim().toLowerCase();
  const banner = document.getElementById("banner");
  banner.innerHTML = model.problems.map((p) => "<div class='banner'>" + escapeHtml(p)
    + "</div>").join("");
  const parts = [];
  let pendingChoices = [];
  let shown = 0;
  for (const group of model.groups) {
    const rows = group.rows.filter((row) => !filter
      || row.title.toLowerCase().includes(filter) || group.name.toLowerCase().includes(filter));
    if (rows.length === 0) continue;
    shown += rows.length;
    parts.push("<h2>" + escapeHtml(group.name) + "</h2><div class='card'>");
    for (const row of rows) {
      const isRecording = recordingId === row.id;
      const label = isRecording ? "Type a shortcut…" : keycaps(row.shortcut);
      const keyClass = "keys" + (isRecording ? " recording" : "") + (row.shortcut ? "" : " none");
      parts.push("<div class='row'><div class='title'>" + escapeHtml(row.title)
        + (row.is_default ? "" : "<span class='changed' title='Changed'></span>") + "</div>"
        + "<button class='" + keyClass + "' data-record='" + escapeHtml(row.id)
        + "' title='Click, then press the new shortcut'>" + label + "</button>"
        + "<button class='icon' data-clear='" + escapeHtml(row.id) + "' title='Remove the shortcut'"
        + (row.shortcut ? "" : " hidden") + ">✕</button>"
        + "<button class='icon' data-reset='" + escapeHtml(row.id) + "' title='Default: "
        + escapeHtml(row.default_text) + "'" + (row.is_default ? " hidden" : "") + ">↺</button>"
        + "</div>");
      if (model.pending && model.pending.id === row.id) {
        const note = pendingNote(model.pending);
        parts.push(note.html);
        pendingChoices = note.choices;
      } else if (row.macos_conflict) {
        parts.push("<div class='note warn'>macOS also uses this shortcut for “"
          + escapeHtml(row.macos_conflict.name) + "”.<div class='choices'><button data-macos='"
          + escapeHtml(row.id) + "'>Turn off the macOS shortcut</button></div></div>");
      }
    }
    parts.push("</div>");
  }
  if (shown === 0) parts.push("<p class='empty'>No action matches the filter.</p>");
  const list = document.getElementById("list");
  list.innerHTML = parts.join("");
  list.querySelectorAll("[data-record]").forEach((button) =>
    button.addEventListener("click", () => {
      recordingId = button.dataset.record;
      post({ kind: "record_start" });
      render(model);
    }));
  list.querySelectorAll("[data-clear]").forEach((button) => button.addEventListener("click",
    () => post({ kind: "remove", id: button.dataset.clear })));
  list.querySelectorAll("[data-reset]").forEach((button) => button.addEventListener("click",
    () => post({ kind: "default", id: button.dataset.reset })));
  list.querySelectorAll("[data-macos]").forEach((button) => button.addEventListener("click",
    () => post({ kind: "turn_off_macos", id: button.dataset.macos })));
  list.querySelectorAll("[data-choice]").forEach((button) => button.addEventListener("click",
    () => post(Object.assign({ kind: "resolve" }, pendingChoices[Number(button.dataset.choice)]))));
};
document.getElementById("filter").addEventListener("input", () => render(model));
document.addEventListener("keydown", (event) => {
  if (recordingId === null) return;
  event.preventDefault();
  event.stopPropagation();
  if (["Shift", "Control", "Alt", "Meta", "CapsLock", "Fn"].includes(event.key)) return;
  const modifiers = [];
  if (event.ctrlKey) modifiers.push("ctrl");
  if (event.altKey) modifiers.push("alt");
  if (event.shiftKey) modifiers.push("shift");
  if (event.metaKey) modifiers.push("cmd");
  const id = recordingId;
  recordingId = null;
  const key = keyName(event.code);
  if (event.code === "Escape" && modifiers.length === 0) {
    post({ kind: "record_cancel" });
  } else if (event.code === "Backspace" && modifiers.length === 0) {
    post({ kind: "remove", id: id });
  } else if (key === undefined) {
    post({ kind: "record_unknown", code: event.code });
  } else {
    post({ kind: "record", id: id, modifiers: modifiers, key: key });
  }
}, true);
document.getElementById("reset-all").addEventListener("click", () => {
  if (confirm("Give every action its default shortcut again?")) post({ kind: "reset_all" });
});
document.getElementById("done").addEventListener("click", () => post({ kind: "done" }));
]]

---@param model ShortcutWindowModel
---@return string html
function shortcut_window.build_page(model)
    return table.concat({
        "<!DOCTYPE html><html><head><meta charset='utf-8'><style>",
        STYLE,
        "</style></head><body><header><h1>Keyboard Shortcuts</h1>",
        "<p class='lead'>Click a shortcut and press the new keys. Escape cancels, and Delete",
        " removes the shortcut. The window checks the shortcuts of macOS, and cannot see the",
        " shortcuts of other applications.</p>",
        "<input id='filter' type='search' placeholder='Filter actions'>",
        "<div id='banner'></div></header><main id='list'></main>",
        "<footer><button id='reset-all'>Restore All Defaults</button>",
        "<span class='hint'>Saved in ~/.hammerspoon/keyboard-shortcuts.json</span>",
        "<button id='done' class='primary'>Done</button></footer>",
        "<script>",
        SCRIPT,
        "render(",
        hs.json.encode(model),
        ");</script></body></html>",
    })
end

---@param shortcut Shortcut
---@return MacosShortcut|nil
local function find_macos_conflict(shortcut)
    return macos_shortcut_settings.find_conflict(shortcut.modifiers, shortcut.key)
end

---@param window ShortcutWindow
---@param is_first boolean whether the page loads, rather than drawing its list again
local function render(window, is_first)
    window.model = shortcut_window.build_model(
        window.center,
        window.problems,
        window.pending,
        find_macos_conflict
    )
    if is_first then
        window.view:html(shortcut_window.build_page(window.model))
    else
        window.view:evaluateJavaScript("render(" .. hs.json.encode(window.model) .. ")")
    end
end

---@param window ShortcutWindow
---@param id string
---@param value Shortcut|false|nil
local function change(window, id, value)
    window.center:resume()
    window.pending = nil
    window.problems = window.center:set_override(id, value)
    render(window, false)
end

---Applies a recorded shortcut at once, or keeps it pending when another action or macOS uses it.
---@param window ShortcutWindow
---@param id string
---@param shortcut Shortcut
local function record(window, id, shortcut)
    window.center:resume()
    local holder = window.center:find_holder(shortcut, id)
    local pending = {
        id = id,
        shortcut = shortcut,
        holder = holder and { id = holder.id, title = holder.title },
        macos = find_macos_conflict(shortcut),
    }
    if not pending.holder and not pending.macos then
        change(window, id, shortcut)
        return
    end
    window.pending = pending
    window.problems = {}
    render(window, false)
end

---@param window ShortcutWindow
---@param choice table the choice of the user: remove_holder, turn_off_macos or cancel
local function resolve(window, choice)
    local pending = window.pending
    if not pending or choice.cancel then
        window.pending = nil
        render(window, false)
        return
    end
    local function finish()
        if choice.remove_holder and pending.holder then
            window.center:set_override(pending.holder.id, false)
        end
        change(window, pending.id, pending.shortcut)
    end
    if choice.turn_off_macos and pending.macos then
        macos_shortcut_settings.turn_off(pending.macos, function(error_message)
            if error_message then
                window.pending = nil
                window.problems = { error_message }
                render(window, false)
                return
            end
            finish()
        end)
        return
    end
    finish()
end

---Turns off the macOS shortcut that the shortcut of an action collides with.
---@param window ShortcutWindow
---@param id string
local function turn_off_macos_for(window, id)
    local shortcut = window.center:find_shortcut(id)
    local conflict = shortcut and find_macos_conflict(shortcut)
    if not conflict then
        render(window, false)
        return
    end
    macos_shortcut_settings.turn_off(conflict, function(error_message)
        window.problems = error_message and { error_message } or {}
        render(window, false)
    end)
end

---@param window ShortcutWindow
local function close(window)
    window.center:resume()
    window.on_closed()
end

---@param window ShortcutWindow
---@param body table the message of the page
local function handle_message(window, body)
    if type(body) ~= "table" then
        return
    end
    if body.kind == "record_start" then
        window.pending = nil
        window.center:pause()
    elseif body.kind == "record_cancel" then
        window.center:resume()
        render(window, false)
    elseif body.kind == "record_unknown" then
        window.center:resume()
        window.problems = {
            string.format("The key %s has no name in Hammerspoon.", tostring(body.code)),
        }
        render(window, false)
    elseif body.kind == "record" and type(body.id) == "string" and type(body.key) == "string" then
        record(window, body.id, { modifiers = body.modifiers or {}, key = body.key })
    elseif body.kind == "resolve" then
        resolve(window, body)
    elseif body.kind == "remove" and type(body.id) == "string" then
        change(window, body.id, false)
    elseif body.kind == "default" and type(body.id) == "string" then
        change(window, body.id, nil)
    elseif body.kind == "reset_all" then
        window.pending = nil
        window.problems = window.center:reset_all()
        render(window, false)
    elseif body.kind == "turn_off_macos" and type(body.id) == "string" then
        turn_off_macos_for(window, body.id)
    elseif body.kind == "done" then
        close(window)
        window.view:delete()
    end
end

---Hammerspoon comes to the front first, because a window of an application in the back takes no
---key presses.
---@param window ShortcutWindow
local function focus(window)
    hs.focus()
    window.view:bringToFront()
    local hs_window = window.view:hswindow()
    if hs_window then
        hs_window:focus()
    end
end

---@param center ShortcutCenter
---@param on_closed fun()
---@return ShortcutWindow
function shortcut_window.open(center, on_closed)
    local window = { center = center, problems = {}, pending = nil, on_closed = on_closed }
    local screen_frame = hs.screen.mainScreen():frame()
    local user_content = hs.webview.usercontent.new(MESSAGE_HANDLER)
    user_content:setCallback(function(message)
        handle_message(window, message.body)
    end)
    window.view = hs
        .webview
        .new({
            x = screen_frame.x + (screen_frame.w - WINDOW_SIZE.w) / 2,
            y = screen_frame.y + (screen_frame.h - WINDOW_SIZE.h) / 2,
            w = WINDOW_SIZE.w,
            h = WINDOW_SIZE.h,
        }, {}, user_content)
        :windowTitle("Keyboard Shortcuts")
        :windowStyle({ "titled", "closable", "resizable" })
        :allowTextEntry(true)
        -- Escape cancels a recording, so it does not close the window.
        :closeOnEscape(
            false
        )
        :deleteOnClose(true)
        :windowCallback(function(action)
            if action == "closing" then
                close(window)
            end
        end)
    render(window, true)
    window.view:show()
    focus(window)
    return window
end

---@param window ShortcutWindow
function shortcut_window.bring_to_front(window)
    render(window, false)
    focus(window)
end

return shortcut_window
