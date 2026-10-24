local highlight_colors = require("desktop_manager.core.highlight_colors")

---The window that picks the colors of the search of the windows.
---A preview in the style of the search panel follows each move of a picker or a slider, and each
---choice is saved at once, so that the next search uses it without a reload of Hammerspoon.
local color_window = {}

local MESSAGE_HANDLER = "colors"
local WINDOW_SIZE = { w = 640, h = 760 }

local LABELS = {
    selection = { label = "Selection", description = "The selected window or application" },
    hover = { label = "Hover", description = "The application under the mouse pointer" },
    strong_match = {
        label = "Strong match",
        description = "A title or name that matches the words well",
    },
    medium_match = {
        label = "Medium match",
        description = "A title or name that matches the words in part",
    },
    weak_match = {
        label = "Weak match",
        description = "A title or name that matches the words a little",
    },
}

---@class ColorWindowActions
---@field read_colors fun(): HighlightColors the colors that the search uses now
---@field read_base fun(): HighlightColors the colors of the setting, which Default brings back
---@field set_colors fun(chosen: table<string, table>) saves the colors that the window chose
---@field on_closed fun()

---@class ColorWindow
---@field view table the hs.webview
---@field actions ColorWindowActions
---@field model table the content of the page when the window opened

---@param colors HighlightColors
---@return table<string, table> each color as hex and alpha, by name
local function to_page_colors(colors)
    local page_colors = {}
    for _, name in ipairs(highlight_colors.NAMES) do
        local hex, alpha = highlight_colors.to_hex_and_alpha(colors[name])
        page_colors[name] = { hex = hex, alpha = alpha }
    end
    return page_colors
end

---@param actions ColorWindowActions
---@return table the content of the page: the colors now, the defaults, the presets and the labels
local function build_model(actions)
    local presets = {}
    for _, preset in ipairs(highlight_colors.PRESETS) do
        table.insert(presets, { name = preset.name, colors = to_page_colors(preset.colors) })
    end
    local rows = {}
    for _, name in ipairs(highlight_colors.NAMES) do
        table.insert(rows, {
            name = name,
            label = LABELS[name].label,
            description = LABELS[name].description,
        })
    end
    return {
        colors = to_page_colors(actions.read_colors()),
        defaults = to_page_colors(actions.read_base()),
        presets = presets,
        rows = rows,
    }
end

local STYLE = [[
:root { color-scheme: light dark; --accent: #0a84ff; --card: rgba(127, 127, 127, 0.08);
  --line: rgba(127, 127, 127, 0.18); font: 13px -apple-system, BlinkMacSystemFont, sans-serif; }
body { margin: 0; padding: 16px 20px 70px; }
h1 { font-size: 17px; margin: 0 0 4px; }
h2 { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: GrayText;
  margin: 18px 0 6px 4px; }
.lead { margin: 0 0 12px; color: GrayText; }
.preview { background: rgba(31, 31, 31, 0.97); color: white; border-radius: 14px; padding: 14px;
  box-shadow: 0 6px 24px rgba(0, 0, 0, 0.25); }
.field { background: rgba(255, 255, 255, 0.1); border-radius: 8px; padding: 7px 10px;
  margin-bottom: 12px; }
.field .typed { color: white; } .field .caret { opacity: 0.6; }
.grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
.tile { border-radius: 9px; padding: 6px; }
.thumb { height: 52px; border-radius: 5px; background: linear-gradient(135deg, #3a3f4b, #23262d);
  margin-bottom: 5px; }
.tile .name { font-size: 11px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tile .app { font-size: 10px; color: rgba(255, 255, 255, 0.7); }
.apps { display: flex; gap: 6px; justify-content: center; margin-top: 12px; }
.app-button { border-radius: 9px; padding: 6px 10px; text-align: center; font-size: 10px; }
.app-button .icon { width: 28px; height: 28px; border-radius: 7px; margin: 0 auto 3px;
  background: linear-gradient(135deg, #5b8def, #3557c4); }
.presets { display: flex; gap: 8px; flex-wrap: wrap; }
.preset { display: flex; align-items: center; gap: 6px; padding: 5px 10px; border-radius: 8px;
  border: 1px solid var(--line); background: Canvas; cursor: pointer; font: inherit; }
.preset:hover { border-color: var(--accent); }
.swatch { width: 12px; height: 12px; border-radius: 3px; display: inline-block;
  border: 1px solid rgba(127, 127, 127, 0.4); }
.card { background: var(--card); border-radius: 10px; overflow: hidden; }
.row { display: flex; align-items: center; gap: 12px; padding: 9px 12px;
  border-top: 1px solid var(--line); }
.row:first-child { border-top: none; }
.label { flex: 1; } .label .description { color: GrayText; font-size: 11px; }
input[type=color] { width: 38px; height: 26px; border: none; padding: 0; background: none;
  cursor: pointer; }
input[type=range] { width: 120px; }
.percent { width: 38px; text-align: right; font-variant-numeric: tabular-nums; color: GrayText; }
.reset { border: none; background: none; cursor: pointer; color: GrayText; font-size: 14px;
  width: 24px; border-radius: 5px; }
.reset:hover { background: var(--card); color: CanvasText; }
.reset[disabled] { visibility: hidden; }
footer { position: fixed; bottom: 0; left: 0; right: 0; display: flex;
  justify-content: space-between; align-items: center; padding: 10px 20px; background: Canvas;
  border-top: 1px solid var(--line); }
footer button { font: inherit; padding: 3px 12px; border-radius: 6px; border: 1px solid var(--line);
  background: Canvas; cursor: pointer; }
footer button.primary { background: var(--accent); color: white; border-color: var(--accent); }
footer .hint { color: GrayText; font-size: 11px; }
]]

local SCRIPT = [[
const post = (body) => window.webkit.messageHandlers.colors.postMessage(body);
const colors = JSON.parse(JSON.stringify(model.colors));
const rgba = (color) => {
  const value = parseInt(color.hex.slice(1), 16);
  return "rgba(" + (value >> 16 & 255) + ", " + (value >> 8 & 255) + ", " + (value & 255) + ", "
    + color.alpha + ")";
};
const same = (first, second) => first.hex.toUpperCase() === second.hex.toUpperCase()
  && Math.abs(first.alpha - second.alpha) < 0.005;
const paint = () => {
  document.querySelectorAll("[data-paint]").forEach((element) => {
    element.style.background = rgba(colors[element.dataset.paint]);
  });
  for (const row of model.rows) {
    const color = colors[row.name];
    document.getElementById("color-" + row.name).value = color.hex.toLowerCase();
    document.getElementById("alpha-" + row.name).value = Math.round(color.alpha * 100);
    document.getElementById("percent-" + row.name).textContent =
      Math.round(color.alpha * 100) + "%";
    document.getElementById("reset-" + row.name).disabled = same(color, model.defaults[row.name]);
  }
};
const save = () => post({ kind: "set", colors: colors });
const rows = document.getElementById("rows");
rows.innerHTML = model.rows.map((row) => "<div class='row'><div class='label'>" + row.label
  + "<div class='description'>" + row.description + "</div></div>"
  + "<input type='color' id='color-" + row.name + "' title='Pick the color'>"
  + "<input type='range' id='alpha-" + row.name + "' min='0' max='100' title='Opacity'>"
  + "<span class='percent' id='percent-" + row.name + "'></span>"
  + "<button class='reset' id='reset-" + row.name + "' title='Default'>↺</button></div>").join("");
for (const row of model.rows) {
  const picker = document.getElementById("color-" + row.name);
  const slider = document.getElementById("alpha-" + row.name);
  picker.addEventListener("input", () => {
    colors[row.name].hex = picker.value.toUpperCase();
    paint();
  });
  picker.addEventListener("change", save);
  slider.addEventListener("input", () => { colors[row.name].alpha = slider.value / 100; paint(); });
  slider.addEventListener("change", save);
  document.getElementById("reset-" + row.name).addEventListener("click", () => {
    colors[row.name] = Object.assign({}, model.defaults[row.name]);
    paint();
    save();
  });
}
document.getElementById("presets").innerHTML = model.presets.map((preset, index) =>
  "<button class='preset' data-preset='" + index + "'><span class='swatch' style='background:"
  + rgba(preset.colors.selection) + "'></span><span class='swatch' style='background:"
  + rgba(preset.colors.strong_match) + "'></span>" + preset.name + "</button>").join("");
document.querySelectorAll("[data-preset]").forEach((button) =>
  button.addEventListener("click", () => {
    const preset = model.presets[Number(button.dataset.preset)];
    for (const row of model.rows) colors[row.name] = Object.assign({}, preset.colors[row.name]);
    paint();
    save();
  }));
document.getElementById("restore").addEventListener("click", () => {
  for (const row of model.rows) colors[row.name] = Object.assign({}, model.defaults[row.name]);
  paint();
  post({ kind: "restore" });
});
document.getElementById("done").addEventListener("click", () => post({ kind: "done" }));
paint();
]]

local PREVIEW = [[
<div class='preview'>
  <div class='field'><span class='typed'>draft</span><span class='caret'>|</span></div>
  <div class='grid'>
    <div class='tile' data-paint='selection'><div class='thumb'></div>
      <div class='name'>Draft.docx</div><div class='app'>Microsoft Word</div></div>
    <div class='tile' data-paint='strong_match'><div class='thumb'></div>
      <div class='name'>Drafts</div><div class='app'>Notes</div></div>
    <div class='tile' data-paint='medium_match'><div class='thumb'></div>
      <div class='name'>Daily report</div><div class='app'>Pages</div></div>
    <div class='tile' data-paint='weak_match'><div class='thumb'></div>
      <div class='name'>Downloads</div><div class='app'>Finder</div></div>
  </div>
  <div class='apps'>
    <div class='app-button' data-paint='selection'><div class='icon'></div>Word</div>
    <div class='app-button' data-paint='hover'><div class='icon'></div>Safari</div>
    <div class='app-button' data-paint='strong_match'><div class='icon'></div>Notes</div>
    <div class='app-button'><div class='icon'></div>Mail</div>
  </div>
</div>
]]

---@param model table
---@return string html
local function build_page(model)
    return table.concat({
        "<!DOCTYPE html><html><head><meta charset='utf-8'><style>",
        STYLE,
        "</style></head><body><h1>Search Colors</h1>",
        "<p class='lead'>The colors behind the selection, the hover and the matches of the search",
        " of the windows. Each change is saved, and the next search shows it.</p>",
        PREVIEW,
        "<h2>Presets</h2><div class='presets' id='presets'></div>",
        "<h2>Colors</h2><div class='card' id='rows'></div>",
        "<footer><button id='restore'>Restore Defaults</button>",
        "<span class='hint'>Saved with the profiles</span>",
        "<button id='done' class='primary'>Done</button></footer>",
        "<script>const model = ",
        hs.json.encode(model),
        ";",
        SCRIPT,
        "</script></body></html>",
    })
end

---@param window ColorWindow
---@param body table the message of the page
local function handle_message(window, body)
    if type(body) ~= "table" then
        return
    end
    if body.kind == "set" and type(body.colors) == "table" then
        local chosen = {}
        for _, name in ipairs(highlight_colors.NAMES) do
            local color = body.colors[name]
            if
                type(color) == "table"
                and highlight_colors.describe_color_fault({
                        hex = color.hex,
                        alpha = color.alpha,
                    })
                    == nil
            then
                chosen[name] = { hex = color.hex, alpha = color.alpha }
            end
        end
        window.actions.set_colors(chosen)
    elseif body.kind == "restore" then
        window.actions.set_colors({})
    elseif body.kind == "done" then
        window.actions.on_closed()
        window.view:delete()
    end
end

---@param window ColorWindow
local function focus(window)
    hs.focus()
    window.view:bringToFront()
    local hs_window = window.view:hswindow()
    if hs_window then
        hs_window:focus()
    end
end

---@param actions ColorWindowActions
---@return ColorWindow
function color_window.open(actions)
    local window = { actions = actions }
    local screen_frame = hs.screen.mainScreen():frame()
    local user_content = hs.webview.usercontent.new(MESSAGE_HANDLER)
    user_content:setCallback(function(message)
        handle_message(window, message.body)
    end)
    window.view = hs.webview
        .new({
            x = screen_frame.x + (screen_frame.w - WINDOW_SIZE.w) / 2,
            y = screen_frame.y + (screen_frame.h - WINDOW_SIZE.h) / 2,
            w = WINDOW_SIZE.w,
            h = WINDOW_SIZE.h,
        }, {}, user_content)
        :windowTitle("Search Colors")
        :windowStyle({ "titled", "closable", "resizable" })
        :allowTextEntry(true)
        :closeOnEscape(true)
        :deleteOnClose(true)
        :windowCallback(function(action)
            if action == "closing" then
                actions.on_closed()
            end
        end)
    window.model = build_model(actions)
    window.view:html(build_page(window.model))
    window.view:show()
    focus(window)
    return window
end

---@param window ColorWindow
function color_window.bring_to_front(window)
    focus(window)
end

return color_window
