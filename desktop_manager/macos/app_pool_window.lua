local app_pool = require("desktop_manager.core.app_pool")

---The window that chooses the managed applications.
---A menu of the menu bar item closes at each click, so the window holds the choice instead, and
---each tick applies at once while the window stays open.
local app_pool_window = {}

local MESSAGE_HANDLER = "appPool"
local WINDOW_SIZE = { w = 460, h = 560 }

---@class AppPoolWindowActions
---@field read_pool fun(): AppPool
---@field list_choices fun(): AppPoolChoice[] the applications of the current mode, for the list
---@field set_mode fun(mode: string)
---@field set_listed fun(bundle_id: string, app_name: string, is_listed: boolean)
---@field on_closed fun()

---@class AppPoolWindow
---@field view table the hs.webview
---@field actions AppPoolWindowActions

---@param text string
---@return string
local function escape_html(text)
    return (
        text:gsub("&", "&amp;")
            :gsub("<", "&lt;")
            :gsub(">", "&gt;")
            :gsub('"', "&quot;")
            :gsub("'", "&#39;")
    )
end

local STYLE = [[
:root { color-scheme: light dark; font: 13px -apple-system, sans-serif; }
body { margin: 16px 18px; }
h1 { font-size: 15px; margin: 0 0 6px; }
p { margin: 6px 0; color: GrayText; }
fieldset { border: none; margin: 10px 0; padding: 0; }
label { display: block; padding: 3px 0; }
.apps { border-top: 1px solid rgba(128, 128, 128, 0.3); margin-top: 8px; padding-top: 6px; }
.warning { color: #c0392b; }
.buttons { position: sticky; bottom: 0; padding: 10px 0 0; text-align: right;
  background: Canvas; }
button { font-size: 13px; padding: 3px 14px; }
]]

local SCRIPT = [[
const post = (body) => window.webkit.messageHandlers.appPool.postMessage(body);
const warning = document.getElementById("empty-warning");
const updateWarning = () => {
  const mode = document.querySelector("input[name=mode]:checked").value;
  const ticked = document.querySelectorAll("input.app:checked").length;
  warning.hidden = !(mode === "manage_listed" && ticked === 0);
};
document.querySelectorAll("input[name=mode]").forEach((radio) =>
  radio.addEventListener("change", () => post({ kind: "mode", mode: radio.value })));
document.querySelectorAll("input.app").forEach((box) =>
  box.addEventListener("change", () => {
    post({ kind: "tick", bundle_id: box.dataset.bundleId, app_name: box.dataset.appName,
      is_listed: box.checked });
    updateWarning();
  }));
document.getElementById("done").addEventListener("click", () => post({ kind: "done" }));
updateWarning();
]]

---The page of the window, with the modes, the ticks of the current mode and a Done button.
---@param pool AppPool
---@param choices AppPoolChoice[]
---@return string html
function app_pool_window.build_page(pool, choices)
    local parts = {
        "<!DOCTYPE html><html><head><meta charset='utf-8'><style>",
        STYLE,
        "</style></head><body>",
        "<h1>Managed applications</h1>",
        "<p>The desktop manager minimizes, moves and records the windows of the managed"
            .. " applications, and macOS keeps managing the others. The choice holds for every"
            .. " profile, and each tick applies at once.</p>",
        "<fieldset>",
    }
    for _, mode in ipairs(app_pool.all_modes()) do
        table.insert(
            parts,
            string.format(
                "<label><input type='radio' name='mode' value='%s'%s> %s</label>",
                mode,
                pool.mode == mode and " checked" or "",
                escape_html(app_pool.label_of(mode))
            )
        )
    end
    table.insert(parts, "</fieldset><div class='apps'>")
    if #choices == 0 then
        table.insert(parts, "<p>No application has a window open.</p>")
    end
    for _, choice in ipairs(choices) do
        table.insert(
            parts,
            string.format(
                "<label><input type='checkbox' class='app' data-bundle-id=\"%s\""
                    .. ' data-app-name="%s"%s> %s</label>',
                escape_html(choice.bundle_id),
                escape_html(choice.app_name),
                choice.is_listed and " checked" or "",
                escape_html(choice.app_name)
            )
        )
    end
    table.insert(
        parts,
        "</div><p>The list shows the applications with a window open and the ticked ones.</p>"
    )
    table.insert(
        parts,
        "<p id='empty-warning' class='warning' hidden>No application is ticked, so the desktop"
            .. " manager manages no window.</p>"
    )
    table.insert(parts, "<div class='buttons'><button id='done'>Done</button></div>")
    table.insert(parts, "<script>" .. SCRIPT .. "</script></body></html>")
    return table.concat(parts)
end

---@param window AppPoolWindow
local function render(window)
    window.view:html(
        app_pool_window.build_page(window.actions.read_pool(), window.actions.list_choices())
    )
end

---@param window AppPoolWindow
---@param body table the message of the page
local function handle_message(window, body)
    if type(body) ~= "table" then
        return
    end
    if body.kind == "mode" and app_pool.is_valid_mode(body.mode) then
        window.actions.set_mode(body.mode)
        -- The ticks of the other mode show once the page is drawn again.
        render(window)
    elseif body.kind == "tick" and type(body.bundle_id) == "string" then
        window.actions.set_listed(
            body.bundle_id,
            tostring(body.app_name or body.bundle_id),
            body.is_listed == true
        )
    elseif body.kind == "done" then
        window.actions.on_closed()
        window.view:delete()
    end
end

---Hammerspoon comes to the front first, because a window of an application in the back takes no
---key presses, such as Escape.
---@param window AppPoolWindow
local function focus(window)
    hs.focus()
    window.view:bringToFront()
    local hs_window = window.view:hswindow()
    if hs_window then
        hs_window:focus()
    end
end

---@param actions AppPoolWindowActions
---@return AppPoolWindow
function app_pool_window.open(actions)
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
        :windowTitle("Managed applications")
        :windowStyle({ "titled", "closable", "resizable" })
        :allowTextEntry(true)
        :closeOnEscape(true)
        :deleteOnClose(true)
        :windowCallback(function(action)
            if action == "closing" then
                actions.on_closed()
            end
        end)
    render(window)
    window.view:show()
    focus(window)
    return window
end

---Draws the list again, with the applications that have a window now, and brings the window to the
---front.
---@param window AppPoolWindow
function app_pool_window.bring_to_front(window)
    render(window)
    focus(window)
end

return app_pool_window
