---@meta

---The signatures of the functions of Hammerspoon that the code calls with arguments that
---`tests/fake_hammerspoon.lua` leaves out, as the documentation of Hammerspoon 1.1.1 gives them.
---`hs.canvas.new` is declared as well, because it returns the canvas whose method
---`behaviorAsLabels` is one of those functions.
---lua-language-server reads this file alone, and nothing loads it at run time.
---Without it, lua-language-server takes each signature from `tests/fake_hammerspoon.lua`, whose
---functions leave out the arguments that the fake ignores.

hs = {}

---@param value any
---@param options? table such as `{ newline = " ", indent = "" }`
---@return string
function hs.inspect(value, options) end

hs.logger = {}

---@param id string
---@param log_level? string|integer
---@return table an hs.logger
function hs.logger.new(id, log_level) end

hs.alert = {}

---@param text string
---@param style_or_seconds? table|number the style, or the seconds when the style is left out
---@param screen? table an hs.screen
---@param seconds? number
---@return string the id of the alert
function hs.alert.show(text, style_or_seconds, screen, seconds) end

hs.dialog = {}

---@param message string
---@param details string the informative text under the message
---@param default_text? string
---@param button_one? string
---@param button_two? string
---@param is_secure? boolean
---@return string button the title of the button that the user pressed
---@return string text
function hs.dialog.textPrompt(message, details, default_text, button_one, button_two, is_secure) end

---@param message string
---@param details string the informative text under the message
---@param button_one? string
---@param button_two? string
---@param style? string "warning", "informational" or "critical"
---@return string the title of the button that the user pressed
function hs.dialog.blockAlert(message, details, button_one, button_two, style) end

hs.json = {}

---@param value any
---@param is_pretty_printed? boolean
---@return string
function hs.json.encode(value, is_pretty_printed) end

---@param data table
---@param path string
---@param is_pretty_printed? boolean
---@param replaces_file? boolean
---@return boolean is_written
function hs.json.write(data, path, is_pretty_printed, replaces_file) end

hs.eventtap = {}

---@param modifiers string[]
---@param key string
---@param delay_microseconds? integer
---@param application? table an hs.application that receives the keys
function hs.eventtap.keyStroke(modifiers, key, delay_microseconds, application) end

hs.spaces = {}
hs.spaces.watcher = {}

---@param handler fun(space_number: integer)
---@return table an hs.spaces.watcher
function hs.spaces.watcher.new(handler) end

---@class hs.window.filter
local window_filter = {}

---@param filter table
---@return hs.window.filter
function window_filter:setDefaultFilter(filter) end

hs.window = {}
hs.window.filter = {}

---@param filter? any
---@param log_name? string
---@param log_level? string|integer
---@return hs.window.filter
function hs.window.filter.new(filter, log_name, log_level) end

---@class hs.canvas
local canvas = {}

---@param labels string[]
---@return hs.canvas
function canvas:behaviorAsLabels(labels) end

hs.canvas = {}

---@param frame table
---@return hs.canvas
function hs.canvas.new(frame) end

hs.webview = {}

---@param frame table
---@param preferences? table
---@param user_content? table an hs.webview.usercontent
---@return table an hs.webview
function hs.webview.new(frame, preferences, user_content) end
