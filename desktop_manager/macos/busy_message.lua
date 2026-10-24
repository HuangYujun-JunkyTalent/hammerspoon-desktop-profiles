local canvas_elements = require("desktop_manager.macos.canvas_elements")

---A message at the top of every screen during every operation of the desktop manager that takes
---time, so that the user waits before working with the windows.
---The operations are a switch, a restore, a change of monitors, an addition or a removal of
---desktops, a press in Mission Control and the opening of a window, and the message also shows
---while Mission Control shows.
---The canvas joins every desktop, because Mission Control and the moves of windows change the
---desktops in view while the message shows, and an hs.alert stays on the desktop where it appeared.
local busy_message = {}

local BACKGROUND_COLOR = { white = 0.12, alpha = 0.92 }
local TEXT_COLOR = { white = 1, alpha = 1 }
local TEXT_STYLE = { font = ".AppleSystemUIFont", size = 15 }
local PADDING = { w = 18, h = 10 }
local TOP_MARGIN = 12

---@class BusyMessage
---@field canvases table[] one hs.canvas per screen

---@param text string
---@param screen_frame table the frame of a screen without the menu bar and the Dock
---@param text_size table the w and h of the text
---@return table canvas an hs.canvas
local function show_on_screen(text, screen_frame, text_size)
    local w = math.ceil(text_size.w) + 2 * PADDING.w
    local h = math.ceil(text_size.h) + 2 * PADDING.h
    local canvas = hs.canvas.new({
        x = screen_frame.x + (screen_frame.w - w) / 2,
        y = screen_frame.y + TOP_MARGIN,
        w = w,
        h = h,
    })
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
    canvas:replaceElements({
        canvas_elements.build_rounded_rectangle(nil, BACKGROUND_COLOR, h / 2, nil),
        {
            type = "text",
            text = text,
            textFont = TEXT_STYLE.font,
            textSize = TEXT_STYLE.size,
            textColor = TEXT_COLOR,
            frame = { x = PADDING.w, y = PADDING.h, w = w - 2 * PADDING.w, h = h - 2 * PADDING.h },
        },
    })
    canvas:show()
    return canvas
end

---@param desktop_number integer
---@param slot_key string
---@return string the text of the message while Mission Control shows the desktop
function busy_message.describe_showing_desktop(desktop_number, slot_key)
    return string.format("Showing desktop %d of %s… please wait", desktop_number, slot_key)
end

---@param text string
---@return BusyMessage
function busy_message.show(text)
    local text_size = hs.drawing.getTextDrawingSize(text, TEXT_STYLE)
    local canvases = {}
    for _, screen in ipairs(hs.screen.allScreens()) do
        table.insert(canvases, show_on_screen(text, screen:frame(), text_size))
    end
    return { canvases = canvases }
end

---@param message BusyMessage
function busy_message.close(message)
    for _, canvas in ipairs(message.canvases) do
        canvas:delete()
    end
end

return busy_message
