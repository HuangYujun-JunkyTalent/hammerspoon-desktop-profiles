local macos_shortcut_settings = require("keyboard_shortcuts.macos.macos_shortcut_settings")
local shortcut_window_model = require("keyboard_shortcuts.core.shortcut_window_model")
local web_window = require("keyboard_shortcuts.macos.web_window")

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

---@class ShortcutWindow
---@field web_window WebWindow
---@field center ShortcutCenter
---@field problems string[] the problems of the last change, shown above the list
---@field pending PendingShortcut|nil
---@field model ShortcutWindowModel the content that the page shows now
---@field on_closed fun()

local STYLE = [[
body { margin: 0; }
header { position: sticky; top: 0; z-index: 2; padding: 16px 20px 10px; background: Canvas;
  border-bottom: 1px solid var(--line); }
.lead { margin: 0 0 10px; color: GrayText; }
#filter { width: 100%; box-sizing: border-box; font-size: 13px; padding: 6px 10px;
  border-radius: 7px; border: 1px solid var(--line); background: var(--card); }
main { padding: 6px 20px 70px; }
.row { display: flex; align-items: center; gap: 10px; padding: 8px 12px;
  border-top: 1px solid var(--line); }
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
.note button { font: inherit; padding: 3px 12px; border-radius: 6px;
  border: 1px solid var(--line); background: Canvas; cursor: pointer; }
.note button.primary { background: var(--accent); color: white; border-color: var(--accent); }
.banner { margin: 10px 0 0; padding: 8px 10px; border-radius: 8px;
  background: rgba(208, 54, 45, 0.13); }
.empty { color: GrayText; padding: 12px; }
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
        web_window.SHARED_STYLE,
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

---@param macos_shortcut_list MacosShortcut[] the shortcuts of macOS that
---`macos_shortcut_settings.list` returned
---@param shortcut Shortcut
---@return MacosShortcut|nil
local function find_macos_conflict(macos_shortcut_list, shortcut)
    return macos_shortcut_settings.find_conflict(
        macos_shortcut_list,
        shortcut.modifiers,
        shortcut.key
    )
end

---Reads the shortcuts of macOS once and finds the conflict of every row in that list, because each
---read runs `defaults` and blocks Hammerspoon until it ends.
---@param window ShortcutWindow
---@return ShortcutWindowModel the model of the shortcuts, the problems and the pending shortcut of
---the window now
local function build_window_model(window)
    local macos_shortcut_list = macos_shortcut_settings.list()
    return shortcut_window_model.build_model(
        window.center,
        window.problems,
        window.pending,
        function(shortcut)
            return find_macos_conflict(macos_shortcut_list, shortcut)
        end
    )
end

---Builds the model of the window and loads the page, which draws the list.
---@param window ShortcutWindow
local function load_page(window)
    window.model = build_window_model(window)
    window.web_window.view:html(shortcut_window.build_page(window.model))
end

---Builds the model of the window again and draws the list of the loaded page with it.
---@param window ShortcutWindow
local function redraw_list(window)
    window.model = build_window_model(window)
    window.web_window.view:evaluateJavaScript("render(" .. hs.json.encode(window.model) .. ")")
end

---@param window ShortcutWindow
---@param id string
---@param value Shortcut|false|nil
local function change_shortcut(window, id, value)
    window.center:resume()
    window.pending = nil
    window.problems = window.center:set_override(id, value)
    redraw_list(window)
end

---Applies a recorded shortcut at once, or keeps it pending when another action or macOS uses it.
---@param window ShortcutWindow
---@param id string
---@param shortcut Shortcut
local function record_shortcut(window, id, shortcut)
    window.center:resume()
    local holder = window.center:find_holder(shortcut, id)
    local pending = {
        id = id,
        shortcut = shortcut,
        holder = holder and { id = holder.id, title = holder.title },
        macos = find_macos_conflict(macos_shortcut_settings.list(), shortcut),
    }
    if not pending.holder and not pending.macos then
        change_shortcut(window, id, shortcut)
        return
    end
    window.pending = pending
    window.problems = {}
    redraw_list(window)
end

---@param window ShortcutWindow
---@param choice table the choice of the user: remove_holder, turn_off_macos or cancel
local function resolve_pending_shortcut(window, choice)
    local pending = window.pending
    if not pending or choice.cancel then
        window.pending = nil
        redraw_list(window)
        return
    end
    local function finish()
        if choice.remove_holder and pending.holder then
            window.center:set_override(pending.holder.id, false)
        end
        change_shortcut(window, pending.id, pending.shortcut)
    end
    if choice.turn_off_macos and pending.macos then
        macos_shortcut_settings.turn_off(pending.macos, function(error_message)
            if error_message then
                window.pending = nil
                window.problems = { error_message }
                redraw_list(window)
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
    local conflict = shortcut and find_macos_conflict(macos_shortcut_settings.list(), shortcut)
    if not conflict then
        redraw_list(window)
        return
    end
    macos_shortcut_settings.turn_off(conflict, function(error_message)
        window.problems = error_message and { error_message } or {}
        redraw_list(window)
    end)
end

---Resumes the shortcuts, which a recording paused, and reports that the window closed.
---@param window ShortcutWindow
local function finish_closing(window)
    window.center:resume()
    window.on_closed()
end

---The handler of each kind of message of the page, which checks the fields that it reads.
---@type table<string, fun(window: ShortcutWindow, body: table)>
local MESSAGE_KIND_HANDLERS = {
    record_start = function(window)
        window.pending = nil
        window.center:pause()
    end,
    record_cancel = function(window)
        window.center:resume()
        redraw_list(window)
    end,
    record_unknown = function(window, body)
        window.center:resume()
        window.problems = {
            string.format("The key %s has no name in Hammerspoon.", tostring(body.code)),
        }
        redraw_list(window)
    end,
    record = function(window, body)
        if type(body.id) == "string" and type(body.key) == "string" then
            record_shortcut(window, body.id, { modifiers = body.modifiers or {}, key = body.key })
        end
    end,
    resolve = resolve_pending_shortcut,
    remove = function(window, body)
        if type(body.id) == "string" then
            change_shortcut(window, body.id, false)
        end
    end,
    default = function(window, body)
        if type(body.id) == "string" then
            change_shortcut(window, body.id, nil)
        end
    end,
    reset_all = function(window)
        window.pending = nil
        window.problems = window.center:reset_all()
        redraw_list(window)
    end,
    turn_off_macos = function(window, body)
        if type(body.id) == "string" then
            turn_off_macos_for(window, body.id)
        end
    end,
    done = function(window)
        web_window.close(window.web_window)
    end,
}

---@param window ShortcutWindow
---@param body table the message of the page
local function handle_message(window, body)
    local handler = MESSAGE_KIND_HANDLERS[body.kind]
    if handler then
        handler(window, body)
    end
end

---@param center ShortcutCenter
---@param on_closed fun()
---@return ShortcutWindow
function shortcut_window.open(center, on_closed)
    local window = { center = center, problems = {}, pending = nil, on_closed = on_closed }
    window.web_window = web_window.new({
        title = "Keyboard Shortcuts",
        size = WINDOW_SIZE,
        message_handler = MESSAGE_HANDLER,
        -- Escape cancels a recording, so it does not close the window.
        does_escape_close = false,
        on_message = function(body)
            handle_message(window, body)
        end,
        on_closed = function()
            finish_closing(window)
        end,
    })
    load_page(window)
    web_window.show(window.web_window)
    return window
end

---@param window ShortcutWindow
function shortcut_window.bring_to_front(window)
    redraw_list(window)
    web_window.bring_to_front(window.web_window)
end

return shortcut_window
