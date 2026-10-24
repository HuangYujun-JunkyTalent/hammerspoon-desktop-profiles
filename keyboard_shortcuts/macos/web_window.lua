---The frame of the web windows of the tools: a page centred on the main screen, whose script posts
---its messages to one message handler, with a closing action that runs once.
---The window of the shortcuts and the windows of the desktop manager open through this module.
---The module sits in `keyboard_shortcuts/`, because the window of the shortcuts would otherwise
---require a module of the desktop manager.
local web_window = {}

---The rules of style that the pages of the colors and of the shortcuts share, which each page
---follows with its own rules.
web_window.SHARED_STYLE = [[
:root { color-scheme: light dark; --accent: #0a84ff; --card: rgba(127, 127, 127, 0.08);
  --line: rgba(127, 127, 127, 0.18); font: 13px -apple-system, BlinkMacSystemFont, sans-serif; }
h1 { font-size: 17px; margin: 0 0 4px; }
h2 { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: GrayText;
  margin: 18px 0 6px 4px; }
.card { background: var(--card); border-radius: 10px; overflow: hidden; }
.row:first-child { border-top: none; }
footer { position: fixed; bottom: 0; left: 0; right: 0; display: flex;
  justify-content: space-between; align-items: center; padding: 10px 20px; background: Canvas;
  border-top: 1px solid var(--line); }
footer button { font: inherit; padding: 3px 12px; border-radius: 6px; border: 1px solid var(--line);
  background: Canvas; cursor: pointer; }
footer button.primary { background: var(--accent); color: white; border-color: var(--accent); }
footer .hint { color: GrayText; font-size: 11px; }
]]

---@class WebWindowOptions
---@field title string
---@field size table the width `w` and the height `h` of the window
---@field message_handler string the name of the handler to which the script of the page posts
---@field does_escape_close boolean
---@field on_message fun(body: table) runs for each message of the page whose body is a table
---@field on_closed fun() the closing action

---@class WebWindow
---@field view table the hs.webview
---@field on_closed fun()
---@field has_run_closing_action boolean

---@param window WebWindow
local function run_closing_action_once(window)
    if window.has_run_closing_action then
        return
    end
    window.has_run_closing_action = true
    window.on_closed()
end

---Builds the window, out of sight, so that its page loads before `show` brings it to the front.
---@param options WebWindowOptions
---@return WebWindow
function web_window.new(options)
    local window = { on_closed = options.on_closed, has_run_closing_action = false }
    local screen_frame = hs.screen.mainScreen():frame()
    local user_content = hs.webview.usercontent.new(options.message_handler)
    user_content:setCallback(function(message)
        if type(message.body) == "table" then
            options.on_message(message.body)
        end
    end)
    window.view = hs.webview
        .new({
            x = screen_frame.x + (screen_frame.w - options.size.w) / 2,
            y = screen_frame.y + (screen_frame.h - options.size.h) / 2,
            w = options.size.w,
            h = options.size.h,
        }, {}, user_content)
        :windowTitle(options.title)
        :windowStyle({ "titled", "closable", "resizable" })
        :allowTextEntry(true)
        :closeOnEscape(options.does_escape_close)
        :deleteOnClose(true)
        :windowCallback(function(action)
            if action == "closing" then
                run_closing_action_once(window)
            end
        end)
    return window
end

---Hammerspoon comes to the front first, because a window of an application in the back takes no
---key presses, such as Escape.
---@param window WebWindow
function web_window.bring_to_front(window)
    hs.focus()
    window.view:bringToFront()
    local hs_window = window.view:hswindow()
    if hs_window then
        hs_window:focus()
    end
end

---@param window WebWindow
function web_window.show(window)
    window.view:show()
    web_window.bring_to_front(window)
end

---Runs the closing action and deletes the window.
---`hs.webview:delete` calls the window callback with "closing", as the documentation of Hammerspoon
---says, and the closing action still runs once.
---@param window WebWindow
function web_window.close(window)
    run_closing_action_once(window)
    window.view:delete()
end

return web_window
