---The console line that an opening of the search of the windows writes when its panel closes: the
---times of its parts, how long the previews and the new list of the window server blocked
---Hammerspoon, and the longest wait of a key before the search took it.
local search_opening_log = {}

---What happened after the opening of the search, in seconds since the opening.
---@class SearchOpeningTimes
---@field window_count integer the windows of the search when its panel showed
---@field shown_after number when the panel showed, after the Lua of the opening
---@field first_preview_after number|nil when the first preview came, or nil before any preview
---@field last_preview_after number|nil when the last preview came
---@field preview_count integer the previews that came
---@field requested_preview_count integer the previews that the search asked for
---@field preview_blocking_seconds number the time that the previews held Hammerspoon in total
---@field longest_preview_blocking_seconds number the longest time that one preview held it
---@field server_list_after number|nil when the new list of the window server came, or nil before
---it came
---@field server_list_blocking_seconds number|nil the time that the new list held Hammerspoon
---@field key_count integer the keys that the search took
---@field longest_key_wait_seconds number|nil the longest time from a key to the search, or nil
---when no key carried its time

---@param count integer
---@param noun string the noun for one
---@return string such as "1 window" or "12 windows"
local function describe_count(count, noun)
    return string.format("%d %s%s", count, noun, count == 1 and "" or "s")
end

---@param times SearchOpeningTimes
---@return string such as "first preview after 0.064 seconds, 12 of 12 previews by 1.105 seconds,
---blocking Hammerspoon for 0.930 seconds in total and 0.160 seconds at most"
local function describe_previews(times)
    if times.preview_count == 0 then
        return "no preview"
    end
    return string.format(
        "first preview after %.3f seconds, %d of %s by %.3f seconds,"
            .. " blocking Hammerspoon for %.3f seconds in total and %.3f seconds at most",
        times.first_preview_after,
        times.preview_count,
        describe_count(times.requested_preview_count, "preview"),
        times.last_preview_after,
        times.preview_blocking_seconds,
        times.longest_preview_blocking_seconds
    )
end

---@param times SearchOpeningTimes
---@return string
local function describe_server_list(times)
    if not times.server_list_after then
        return "list of the window server not back"
    end
    return string.format(
        "list of the window server after %.3f seconds, blocking Hammerspoon for %.3f seconds",
        times.server_list_after,
        times.server_list_blocking_seconds
    )
end

---@param times SearchOpeningTimes
---@return string
local function describe_keys(times)
    if times.key_count == 0 then
        return "no key"
    end
    if not times.longest_key_wait_seconds then
        return describe_count(times.key_count, "key")
    end
    return string.format(
        "%s, waiting %.3f seconds at most",
        describe_count(times.key_count, "key"),
        times.longest_key_wait_seconds
    )
end

---@param times SearchOpeningTimes
---@return string such as "search of 12 windows: shown after 0.012 seconds, first preview after
---0.064 seconds, 12 of 12 previews by 1.105 seconds, blocking Hammerspoon for 0.930 seconds in
---total and 0.160 seconds at most, list of the window server after 0.203 seconds, blocking
---Hammerspoon for 0.045 seconds, 5 keys, waiting 0.120 seconds at most"
function search_opening_log.describe(times)
    return string.format(
        "search of %s: shown after %.3f seconds, %s, %s, %s",
        describe_count(times.window_count, "window"),
        times.shown_after,
        describe_previews(times),
        describe_server_list(times),
        describe_keys(times)
    )
end

return search_opening_log
