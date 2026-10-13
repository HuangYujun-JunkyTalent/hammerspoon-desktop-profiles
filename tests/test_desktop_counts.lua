local desktop_counts = require("desktop_manager.core.desktop_counts")
local expect = require("tests.expect")
local monitor_configuration = require("desktop_manager.core.monitor_configuration")
local monitor_matching = require("desktop_manager.core.monitor_matching")

local BUILTIN = {
    uuid = "BUILTIN-UUID",
    name = "Built-in Retina Display",
    is_builtin = true,
    frame = { x = 0, y = 25, w = 1440, h = 875 },
}
local DELL = {
    uuid = "DELL-UUID",
    name = "DELL S2725DS",
    is_builtin = false,
    frame = { x = 1440, y = 0, w = 2560, h = 1440 },
}
local BOTH = monitor_configuration.describe({ BUILTIN, DELL }, monitor_matching.BY_COUNT)
local BUILTIN_ALONE = monitor_configuration.describe({ BUILTIN }, monitor_matching.BY_COUNT)

---@param space_ids_by_uuid table<string, integer[]> the desktops of each display, the first in view
---@return DesktopLayout
local function layout_with(space_ids_by_uuid)
    local screens = {}
    for _, uuid in ipairs({ "BUILTIN-UUID", "DELL-UUID" }) do
        local space_ids = space_ids_by_uuid[uuid]
        if space_ids then
            table.insert(screens, {
                screen_uuid = uuid,
                screen_frame = BUILTIN.frame,
                space_ids = space_ids,
                active_space_id = space_ids[1],
            })
        end
    end
    return { screens = screens, focused_space_id = screens[1].space_ids[1] }
end

---@param counts DesktopCounts
---@param configuration MonitorConfiguration
---@param space_ids_by_uuid table<string, integer[]>
---@return DesktopCounts
local function read_into(counts, configuration, space_ids_by_uuid)
    return desktop_counts.update(
        counts,
        desktop_counts.read(configuration, layout_with(space_ids_by_uuid))
    )
end

return {
    a_display_first_seen_keeps_its_desktops = function()
        local counts = read_into(
            desktop_counts.new(),
            BOTH,
            { ["BUILTIN-UUID"] = { 3, 14, 64 }, ["DELL-UUID"] = { 7, 8, 9, 10 } }
        )
        expect.equal(counts.kept, { ["built-in"] = 3, ["external 1"] = 4 })
        expect.equal(counts.last_reading.displays_key, "BUILTIN-UUID;DELL-UUID")
    end,

    the_desktops_that_macos_moves_change_no_count = function()
        local counts = read_into(
            desktop_counts.new(),
            BOTH,
            { ["BUILTIN-UUID"] = { 3, 14, 64 }, ["DELL-UUID"] = { 7, 8, 9, 10 } }
        )
        counts = read_into(counts, BUILTIN_ALONE, { ["BUILTIN-UUID"] = { 3, 14, 64, 8, 9, 10 } })
        expect.equal(counts.kept, { ["built-in"] = 3, ["external 1"] = 4 })
        counts = read_into(
            counts,
            BOTH,
            { ["BUILTIN-UUID"] = { 3, 14, 64, 8, 9, 10 }, ["DELL-UUID"] = { 20 } }
        )
        expect.equal(counts.kept, { ["built-in"] = 3, ["external 1"] = 4 })
    end,

    a_desktop_that_the_user_adds_or_removes_changes_the_count = function()
        local counts =
            read_into(desktop_counts.new(), BUILTIN_ALONE, { ["BUILTIN-UUID"] = { 3, 14 } })
        counts = read_into(counts, BUILTIN_ALONE, { ["BUILTIN-UUID"] = { 3, 14, 70 } })
        expect.equal(counts.kept["built-in"], 3)
        counts = read_into(counts, BUILTIN_ALONE, { ["BUILTIN-UUID"] = { 3, 70 } })
        expect.equal(counts.kept["built-in"], 2)
    end,

    a_desktop_added_beside_moved_ones_counts_and_a_moved_one_removed_does_not = function()
        local counts = read_into(
            desktop_counts.new(),
            BOTH,
            { ["BUILTIN-UUID"] = { 3, 14 }, ["DELL-UUID"] = { 7, 8, 9 } }
        )
        counts = read_into(counts, BUILTIN_ALONE, { ["BUILTIN-UUID"] = { 3, 14, 8, 9 } })
        counts = read_into(counts, BUILTIN_ALONE, { ["BUILTIN-UUID"] = { 3, 14, 8, 9, 71 } })
        expect.equal(counts.kept["built-in"], 3)
        counts = read_into(counts, BUILTIN_ALONE, { ["BUILTIN-UUID"] = { 3, 14, 9, 71 } })
        expect.equal(counts.kept, { ["built-in"] = 3, ["external 1"] = 3 })
    end,

    the_restore_after_a_change_adds_no_desktop_beyond_the_counts = function()
        local counts = read_into(
            desktop_counts.new(),
            BOTH,
            { ["BUILTIN-UUID"] = { 3, 14, 64 }, ["DELL-UUID"] = { 7, 8 } }
        )
        local arrangement = {
            monitor_configuration_key = BOTH.key,
            monitors = {
                { slot_key = "built-in", desktop_count = 6 },
                { slot_key = "external 1", desktop_count = 2 },
                { slot_key = "external 2", desktop_count = 5 },
            },
            focus = nil,
            windows = {},
        }
        local limited = desktop_counts.limit_arrangement(arrangement, counts)
        expect.equal(limited.monitors, {
            { slot_key = "built-in", desktop_count = 3 },
            { slot_key = "external 1", desktop_count = 2 },
            { slot_key = "external 2", desktop_count = 5 },
        })
        expect.equal(arrangement.monitors[1].desktop_count, 6)
    end,

    the_empty_desktops_beyond_the_count_are_removed_from_the_end = function()
        local counts = read_into(
            desktop_counts.new(),
            BOTH,
            { ["BUILTIN-UUID"] = { 3, 14, 64 }, ["DELL-UUID"] = { 7, 8, 9, 10 } }
        )
        local layout = layout_with({
            ["BUILTIN-UUID"] = { 3, 14, 64, 8, 9, 10 },
            ["DELL-UUID"] = { 20, 21, 22, 23 },
        })
        expect.equal(
            desktop_counts.plan_removals(counts, BOTH, layout, { [9] = true, [14] = true }),
            {
                {
                    screen_uuid = "BUILTIN-UUID",
                    slot_key = "built-in",
                    space_ids = { 10, 8 },
                    staying_count = 1,
                },
            }
        )
    end,

    a_desktop_in_view_stays_and_a_display_without_a_count_is_left_alone = function()
        local counts = read_into(desktop_counts.new(), BUILTIN_ALONE, { ["BUILTIN-UUID"] = { 3 } })
        local layout = layout_with({ ["BUILTIN-UUID"] = { 3, 14 }, ["DELL-UUID"] = { 20, 21 } })
        layout.screens[1].active_space_id = 14
        expect.equal(desktop_counts.plan_removals(counts, BOTH, layout, {}), {
            {
                screen_uuid = "BUILTIN-UUID",
                slot_key = "built-in",
                space_ids = {},
                staying_count = 1,
            },
        })
    end,
}
