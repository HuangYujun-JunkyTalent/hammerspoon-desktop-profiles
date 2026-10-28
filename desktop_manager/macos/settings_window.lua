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
---@field read_profile_choices fun(): ProfileConfigurationChoices
---@field set_configuration_managed fun(number: integer, configuration_key: string,
---is_managed: boolean) saves whether the profile arranges the monitor configuration
---@field open_color_window fun()
---@field on_closed fun()

---The monitor configurations that the section of the profiles offers, and the choices of each
---profile.
---@class ProfileConfigurationChoices
---@field configuration_keys string[] the configurations that a profile recorded or left to macOS,
---and the configuration now
---@field current_key string the configuration now
---@field profiles ProfileConfigurationChoice[]

---@class ProfileConfigurationChoice
---@field number integer
---@field name string
---@field unmanaged_keys table<string, boolean> the configurations that the profile leaves to macOS

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
        profile_choices = actions.read_profile_choices(),
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
table.profiles { border-collapse: collapse; width: 100%; }
table.profiles th, table.profiles td { padding: 7px 12px; border-top: 1px solid var(--line);
  text-align: center; font-weight: normal; }
table.profiles th:first-child, table.profiles td:first-child { text-align: left; }
table.profiles thead th { border-top: none; color: GrayText; font-size: 11px; }
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
const renderProfiles = () => {
  const choices = model.profile_choices;
  const escape = (text) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;");
  const keyLabel = (key) => escape(key) + (key === choices.current_key ? " (now)" : "");
  document.getElementById("profiles").innerHTML = "<table class='profiles'><thead><tr><th></th>"
    + choices.configuration_keys.map((key) => "<th>" + keyLabel(key) + "</th>").join("")
    + "</tr></thead><tbody>" + choices.profiles.map((profile) => "<tr><td>" + escape(profile.name)
    + "</td>" + choices.configuration_keys.map((key, index) => "<td><input type='checkbox'"
    + " id='manage-" + profile.number + "-" + index + "'"
    + (profile.unmanaged_keys[key] ? "" : " checked")
    + "></td>").join("") + "</tr>").join("") + "</tbody></table>";
  for (const profile of choices.profiles) {
    choices.configuration_keys.forEach((key, index) => {
      const box = document.getElementById("manage-" + profile.number + "-" + index);
      box.addEventListener("change", () => post({ kind: "manage", number: profile.number,
        configuration_key: key, is_managed: box.checked }));
    });
  }
};
const renderAll = (next) => { render(next); renderProfiles(); };
document.getElementById("colors").addEventListener("click", () => post({ kind: "colors" }));
document.getElementById("done").addEventListener("click", () => post({ kind: "done" }));
renderAll(model);
]]

---@param model table
---@return string html
local function build_page(model)
    return table.concat({
        "<!DOCTYPE html><html><head><meta charset='utf-8'><style>",
        web_window.SHARED_STYLE,
        STYLE,
        "</style></head><body><h1>Settings</h1>",
        "<p class='lead'>A change applies at once and is saved with the profiles.",
        " ↺ brings back the value of default_settings.lua.</p>",
        "<div id='sections'></div>",
        "<h2>Monitor configurations that each profile arranges</h2>",
        "<p class='lead'>Without a tick, the profile leaves the windows and the desktops of that",
        " configuration to macOS while it is active, as while no profile is active.</p>",
        "<div class='card' id='profiles'></div>",
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
    window.web_window.view:evaluateJavaScript("renderAll(" .. hs.json.encode(window.model) .. ")")
end

---A number from the page may arrive as a float, such as 2.0.
---@param value any
---@return integer|nil
local function read_profile_number(value)
    return type(value) == "number" and math.tointeger(value) or nil
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
    elseif body.kind == "manage" then
        local number = read_profile_number(body.number)
        if
            number
            and type(body.configuration_key) == "string"
            and type(body.is_managed) == "boolean"
        then
            window.actions.set_configuration_managed(
                number,
                body.configuration_key,
                body.is_managed
            )
        end
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
