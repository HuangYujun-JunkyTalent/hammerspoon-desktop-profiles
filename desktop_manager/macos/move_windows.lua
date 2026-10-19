local read_desktops = require("desktop_manager.macos.read_desktops")
local retained_timers = require("desktop_manager.macos.retained_timers")

---Moves windows to other desktops of their screens with `hs.spaces.moveWindowToSpace`, by their
---window ids, which reaches also a window that Hammerspoon has not seen.
---The move needs a Hammerspoon with pull request #3889, whose moves end some time after the call
---returns, so a batch waits for all its windows together, each up to its own deadline.
local move_windows = {}

---@class WindowMove
---@field window_id integer
---@field space_id integer a desktop of the screen that the window is on

---@class MoveFailure
---@field window_id integer
---@field space_id integer
---@field message string

---A move that Hammerspoon took, and the time by which its window should be on its desktop.
---@class PendingMove
---@field move WindowMove
---@field deadline number

---@param move WindowMove
---@param message string
---@return MoveFailure
local function fail(move, message)
    return { window_id = move.window_id, space_id = move.space_id, message = message }
end

---Moves each window to its desktop, skips a window that is there already, and calls `on_done` once
---every window has arrived or passed its deadline of `window_move_timeout_seconds` from its call.
---A move that Hammerspoon refuses, or that leaves its window, gives a failure, and the other moves
---go on.
---@param moves WindowMove[]
---@param timing Timing
---@param on_done fun(failures: MoveFailure[])
function move_windows.move_all(moves, timing, on_done)
    local failures, pending = {}, {}
    for _, move in ipairs(moves) do
        if read_desktops.find_window_space_id(move.window_id) ~= move.space_id then
            local is_called, result, message =
                pcall(hs.spaces.moveWindowToSpace, move.window_id, move.space_id)
            if not is_called or not result then
                table.insert(
                    failures,
                    fail(
                        move,
                        string.format(
                            "Hammerspoon refused the move: %s",
                            tostring(message or result)
                        )
                    )
                )
            else
                table.insert(pending, {
                    move = move,
                    deadline = hs.timer.secondsSinceEpoch() + timing.window_move_timeout_seconds,
                })
            end
        end
    end
    ---@return boolean whether no move waits any more
    local function settle_moves()
        local now, still_pending = hs.timer.secondsSinceEpoch(), {}
        for _, entry in ipairs(pending) do
            local has_arrived = read_desktops.find_window_space_id(entry.move.window_id)
                == entry.move.space_id
            if not has_arrived and now >= entry.deadline then
                table.insert(
                    failures,
                    fail(
                        entry.move,
                        string.format(
                            "did not reach its desktop within %g seconds",
                            timing.window_move_timeout_seconds
                        )
                    )
                )
            elseif not has_arrived then
                table.insert(still_pending, entry)
            end
        end
        pending = still_pending
        return #pending == 0
    end
    if settle_moves() then
        on_done(failures)
        return
    end
    local timer
    timer = retained_timers.every(timing.poll_interval_seconds, function()
        if settle_moves() then
            retained_timers.stop(timer)
            on_done(failures)
        end
    end)
end

return move_windows
