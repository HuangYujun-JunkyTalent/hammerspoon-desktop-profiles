local live_settings = require("desktop_manager.core.live_settings")
local web_window = require("keyboard_shortcuts.macos.web_window")

---The window "Settings…", which changes the settings of `live_settings` while the desktop manager
---runs.
---Each choice is saved at once, and the next switch, list or search uses it without a reload of
---Hammerspoon.
local settings_window = {}

local MESSAGE_HANDLER = "settings"
local WINDOW_SIZE = { w = 680, h = 780 }

---@class SettingsWindowActions
---@field read_values fun(): table<string, any> the value of each setting of the window now
---@field read_defaults fun(): table<string, any> the value of each setting in the file
---@field set_value fun(name: string, value: any|nil) saves the value, or returns the setting to
---the value of the file when the value is nil
---@field open_color_window fun()
---@field on_closed fun()

---@class SettingsWindow
---@field web_window WebWindow
---@field actions SettingsWindowActions
---@field model table the content of the page: the sections with their rows, the values and the
---defaults

---@param actions SettingsWindowActions
---@return table
local function build_model(actions)
    local sections, section_by_title = {}, {}
    for _, entry in ipairs(live_settings.ENTRIES) do
        local section = section_by_title[entry.section]
        if not section then
            section = { title = entry.section, rows = {} }
            section_by_title[entry.section] = section
            table.insert(sections, section)
        end
        table.insert(section.rows, {
            name = entry.name,
            label = entry.label,
            description = entry.description,
            kind = entry.kind,
            choices = entry.choices,
            minimum = entry.minimum,
            maximum = entry.maximum,
            step = entry.step,
        })
    end
    return {
        sections = sections,
        values = actions.read_values(),
        defaults = actions.read_defaults(),
    }
end

local STYLE = [[
body { margin: 0; padding: 16px 20px 70px; }
.lead { margin: 0 0 6px; color: GrayText; }
.row { display: flex; align-items: center; gap: 12px; padding: 9px 12px;
  border-top: 1px solid var(--line); }
.label { flex: 1; } .label .description { color: GrayText; font-size: 11px; }
select { font: inherit; max-width: 300px; }
input[type=range] { width: 120px; }
.number { width: 52px; text-align: right; font-variant-numeric: tabular-nums; color: GrayText; }
.size { display: grid; grid-template-columns: auto auto auto; gap: 2px 6px; align-items: center; }
.size span { color: GrayText; font-size: 11px; }
.reset { border: none; background: none; cursor: pointer; color: GrayText; font-size: 14px;
  width: 24px; border-radius: 5px; }
.reset:hover { background: var(--card); color: CanvasText; }
.reset[disabled] { visibility: hidden; }
.link { font: inherit; padding: 3px 12px; border-radius: 6px; border: 1px solid var(--line);
  background: Canvas; cursor: pointer; }
]]

local SCRIPT = [[
const post = (body) => window.webkit.messageHandlers.settings.postMessage(body);
let model = initialModel;
const shown = (value) => Number.isInteger(value) ? String(value)
  : String(Math.round(value * 10000) / 10000);
const same = (first, second) => typeof first === "object"
  ? first.w === second.w && first.h === second.h : first === second;
const slider = (id, row, value) => "<input type='range' id='" + id + "' min='" + row.minimum
  + "' max='" + row.maximum + "' step='" + row.step + "' value='" + value + "'>"
  + "<span class='number' id='" + id + "-shown'>" + shown(value) + "</span>";
const control = (row) => {
  const value = model.values[row.name];
  if (row.kind === "choice") {
    return "<select id='control-" + row.name + "'>" + row.choices.map((choice) =>
      "<option value='" + choice.value + "'" + (choice.value === value ? " selected" : "") + ">"
      + choice.label + "</option>").join("") + "</select>";
  }
  if (row.kind === "number") return slider("control-" + row.name, row, value);
  return "<div class='size'><span>Width</span>" + slider("control-" + row.name + "-w", row, value.w)
    + "<span>Height</span>" + slider("control-" + row.name + "-h", row, value.h) + "</div>";
};
const readControl = (row) => {
  if (row.kind === "choice") return document.getElementById("control-" + row.name).value;
  if (row.kind === "number") return Number(document.getElementById("control-" + row.name).value);
  return { w: Number(document.getElementById("control-" + row.name + "-w").value),
    h: Number(document.getElementById("control-" + row.name + "-h").value) };
};
const render = (next) => {
  model = next;
  document.getElementById("sections").innerHTML = model.sections.map((section) =>
    "<h2>" + section.title + "</h2><div class='card'>" + section.rows.map((row) =>
      "<div class='row'><div class='label'>" + row.label + "<div class='description'>"
      + row.description + "</div></div>" + control(row) + "<button class='reset' id='reset-"
      + row.name + "' title='Default'" + (same(model.values[row.name], model.defaults[row.name])
      ? " disabled" : "") + ">↺</button></div>").join("") + "</div>").join("");
  for (const section of model.sections) {
    for (const row of section.rows) {
      document.querySelectorAll("[id^='control-" + row.name + "']").forEach((element) => {
        if (element.tagName === "SPAN") return;
        element.addEventListener("input", () => {
          const label = document.getElementById(element.id + "-shown");
          if (label) label.textContent = shown(Number(element.value));
        });
        element.addEventListener("change", () =>
          post({ kind: "set", name: row.name, value: readControl(row) }));
      });
      document.getElementById("reset-" + row.name).addEventListener("click", () =>
        post({ kind: "reset", name: row.name }));
    }
  }
};
document.getElementById("colors").addEventListener("click", () => post({ kind: "colors" }));
document.getElementById("done").addEventListener("click", () => post({ kind: "done" }));
render(model);
]]

---@param model table
---@return string html
local function build_page(model)
    return table.concat({
        "<!DOCTYPE html><html><head><meta charset='utf-8'><style>",
        web_window.SHARED_STYLE,
        STYLE,
        "</style></head><body><h1>Settings</h1>",
        "<p class='lead'>Each change is saved with the profiles, and the next switch, list or",
        " search uses it. ↺ returns a setting to the value of default_settings.lua.</p>",
        "<div id='sections'></div>",
        "<h2>Colors</h2><button class='link' id='colors'>Search colors…</button>",
        "<footer><span class='hint'>Saved with the profiles</span>",
        "<button id='done' class='primary'>Done</button></footer>",
        "<script>const initialModel = ",
        hs.json.encode(model),
        ";",
        SCRIPT,
        "</script></body></html>",
    })
end

---Draws the page again with the values now, also after a change that the desktop manager refused.
---@param window SettingsWindow
function settings_window.redraw(window)
    window.model = build_model(window.actions)
    window.web_window.view:evaluateJavaScript("render(" .. hs.json.encode(window.model) .. ")")
end

---@param window SettingsWindow
---@param body table the message of the page
local function handle_message(window, body)
    local entry = type(body.name) == "string" and live_settings.find(body.name) or nil
    if body.kind == "set" and entry then
        local value = live_settings.read_value(entry, body.value)
        if value ~= nil then
            window.actions.set_value(entry.name, value)
        end
        settings_window.redraw(window)
    elseif body.kind == "reset" and entry then
        window.actions.set_value(entry.name, nil)
        settings_window.redraw(window)
    elseif body.kind == "colors" then
        window.actions.open_color_window()
    elseif body.kind == "done" then
        web_window.close(window.web_window)
    end
end

---@param actions SettingsWindowActions
---@return SettingsWindow
function settings_window.open(actions)
    local window = { actions = actions }
    window.web_window = web_window.new({
        title = "Desktop Manager Settings",
        size = WINDOW_SIZE,
        message_handler = MESSAGE_HANDLER,
        does_escape_close = true,
        on_message = function(body)
            handle_message(window, body)
        end,
        on_closed = actions.on_closed,
    })
    window.model = build_model(actions)
    window.web_window.view:html(build_page(window.model))
    web_window.show(window.web_window)
    return window
end

---@param window SettingsWindow
function settings_window.bring_to_front(window)
    web_window.bring_to_front(window.web_window)
end

return settings_window
