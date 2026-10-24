---Reads the output of the helper that captures the previews of the list and the search.
---The helper prints one line per window, `<window id> <seconds of the capture> <image>`, where the
---image is the PNG of the preview as a data URL, or `none` when macOS gave no image.
---A line may arrive over several chunks of the output, because one data URL holds about 100,000
---characters.
local preview_helper_output = {}

---The one form of URL that a line may hold, so that no line makes Hammerspoon fetch a URL from
---elsewhere.
local DATA_URL_PREFIX = "data:image/png;base64,"
local NO_IMAGE = "none"

---One line of the helper.
---@class HelperLine
---@field window_id integer
---@field capture_seconds number the time that the capture of the window took
---@field data_url string|nil the PNG of the preview as a data URL, or nil when macOS gave no image

---@param rest string the start of a line that the output before the chunk left unfinished
---@param chunk string the output that came since
---@return string[] lines the lines that the chunk completes, without their ends
---@return string rest the start of the line that the chunk leaves unfinished
function preview_helper_output.split_lines(rest, chunk)
    local text = rest .. chunk
    local lines = {}
    local line_start = 1
    while true do
        local line_end = text:find("\n", line_start, true)
        if not line_end then
            return lines, text:sub(line_start)
        end
        table.insert(lines, text:sub(line_start, line_end - 1))
        line_start = line_end + 1
    end
end

---@param line string a line without its end
---@return HelperLine|nil the line, or nil for a line that does not read as one
function preview_helper_output.parse_line(line)
    local window_id_text, seconds_text, image = line:match("^(%d+) (%S+) (%S+)$")
    if not window_id_text then
        return nil
    end
    local window_id = math.tointeger(tonumber(window_id_text))
    local capture_seconds = tonumber(seconds_text)
    if not window_id or not capture_seconds then
        return nil
    end
    if image == NO_IMAGE then
        return { window_id = window_id, capture_seconds = capture_seconds, data_url = nil }
    end
    if image:sub(1, #DATA_URL_PREFIX) ~= DATA_URL_PREFIX then
        return nil
    end
    return { window_id = window_id, capture_seconds = capture_seconds, data_url = image }
end

return preview_helper_output
