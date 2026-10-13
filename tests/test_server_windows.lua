local expect = require("tests.expect")
local server_windows = require("desktop_manager.core.server_windows")

local CODE = { bundle_id = "com.microsoft.VSCode", app_name = "Code" }

---@return ServerWindowRow[]
local function build_rows()
    return {
        { window_id = 1, pid = 70, title = "notes.md", x = 0, y = 25, w = 1440, h = 786 },
        { window_id = 2, pid = 70, title = "", x = 0, y = 0, w = 1, h = 1 },
        { window_id = 3, pid = 80, title = "AutoFill", x = 40, y = 60, w = 300, h = 200 },
        { window_id = 4, pid = 70, title = "main.lua", x = 0, y = 25, w = 1440, h = 786 },
        { window_id = 5, pid = 70, title = "known.lua", x = 1440, y = 0, w = 1440, h = 786 },
    }
end

return {
    the_windows_of_an_application_on_a_desktop_out_of_view_are_kept = function()
        local windows = server_windows.select_unreached_windows(
            build_rows(),
            { [1] = 14, [2] = 14, [3] = 14, [5] = 64 },
            { [70] = CODE },
            { [5] = true }
        )
        expect.equal(windows, {
            {
                window_id = 1,
                bundle_id = "com.microsoft.VSCode",
                app_name = "Code",
                title = "notes.md",
                space_id = 14,
                frame = { x = 0, y = 25, w = 1440, h = 786 },
            },
        })
    end,

    the_owners_of_the_windows_out_of_view_are_listed_once = function()
        expect.equal(
            server_windows.list_owner_pids(build_rows(), { [1] = 14, [2] = 14, [3] = 14 }),
            { 70, 80 }
        )
    end,

    a_desktop_holds_the_windows_that_macos_lists_on_it_alone = function()
        expect.equal(
            server_windows.find_occupied_space_ids(
                build_rows(),
                { [1] = { 14 }, [2] = { 15 }, [3] = { 16 }, [4] = { 17, 18 }, [5] = { 64 } },
                { [70] = CODE }
            ),
            { [14] = true, [64] = true }
        )
    end,

    an_earlier_window_stays_while_it_is_out_of_view_and_out_of_reach = function()
        local earlier = server_windows.select_unreached_windows(
            build_rows(),
            { [1] = 14, [4] = 14 },
            { [70] = CODE },
            {}
        )
        local kept = server_windows.keep_unreached_windows(
            earlier,
            { [1] = 64, [4] = 14 },
            { [4] = true }
        )
        expect.equal(#kept, 1)
        expect.equal(kept[1].window_id, 1)
        expect.equal(kept[1].space_id, 64)
        expect.equal(kept[1].frame, { x = 0, y = 25, w = 1440, h = 786 })
        expect.equal(server_windows.keep_unreached_windows(earlier, {}, {}), {})
    end,
}
