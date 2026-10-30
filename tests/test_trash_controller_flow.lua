local default_settings = require("trash.default_settings")
local expect = require("tests.expect")
local fake_hammerspoon = require("tests.fake_hammerspoon")
local trash_controller = require("trash.macos.trash_controller")

local URL_EVENT_NAME = "trash"

---@return table world
local function start_trash_tool()
    local world = fake_hammerspoon.install({
        screens = {},
        displays = {},
        applications = {},
        windows = {},
    })
    trash_controller.start(default_settings.create())
    return world
end

---@param world table
---@param command_id string|nil
---@return table world
local function open_url_of_command(world, command_id)
    world.url_handlers[URL_EVENT_NAME](URL_EVENT_NAME, { command = command_id })
    return world
end

---@param world table
---@return string[] the file names of the scripts that ran
local function list_script_names(world)
    local names = {}
    for _, path in ipairs(world.applescript_runs) do
        table.insert(names, path:match("([^/]+)$"))
    end
    return names
end

return {
    the_command_trash_runs_the_script_that_opens_the_trash = function()
        local world = start_trash_tool()
        world.applescript_output = "opened\n"
        open_url_of_command(world, "trash")
        expect.equal(list_script_names(world), { "open_trash.applescript" })
        expect.equal(world.notifications, {})
    end,

    the_command_empty_trash_runs_the_script_that_empties_the_trash = function()
        local world = start_trash_tool()
        world.applescript_output = "emptied\n"
        open_url_of_command(world, "empty-trash")
        expect.equal(list_script_names(world), { "empty_trash.applescript" })
        expect.equal(world.notifications, {})
    end,

    an_empty_trash_is_reported_in_a_notification = function()
        local world = start_trash_tool()
        world.applescript_output = "empty\n"
        open_url_of_command(world, "empty-trash")
        expect.equal(world.notification_titles, { "Empty Trash" })
        expect.equal(world.notifications, { "The Trash is empty." })
    end,

    a_failed_script_is_reported_with_the_message_of_its_error = function()
        local world = start_trash_tool()
        world.applescript_exit_code = 1
        world.applescript_error_output = "/repository/trash/macos/open_trash.applescript:95:105: "
            .. "execution error: Finder got an error: Not authorized to send Apple events to "
            .. "Finder. (-1743)\n"
        open_url_of_command(world, "trash")
        expect.equal(world.notification_titles, { "Trash failed" })
        expect.equal(
            world.notifications,
            { "Finder got an error: Not authorized to send Apple events to Finder. (-1743)" }
        )
    end,

    a_script_that_osascript_cannot_start_is_reported = function()
        local world = start_trash_tool()
        world.is_applescript_start_failing = true
        open_url_of_command(world, "empty-trash")
        expect.equal(world.notification_titles, { "Empty Trash failed" })
        expect.equal(world.notifications, { "Hammerspoon could not start osascript." })
    end,

    a_second_empty_trash_waits_for_the_end_of_the_first = function()
        local world = start_trash_tool()
        world.holds_applescript_runs = true
        world.applescript_output = "emptied\n"
        open_url_of_command(world, "empty-trash")
        open_url_of_command(world, "empty-trash")
        expect.equal(#world.applescript_runs, 1)
        expect.equal(world.notifications, { "Empty Trash is already running." })
        world.held_applescript_ends[1]()
        open_url_of_command(world, "empty-trash")
        expect.equal(#world.applescript_runs, 2)
    end,

    an_unknown_command_runs_no_script_and_notifies = function()
        local world = open_url_of_command(start_trash_tool(), "shred")
        expect.equal(world.applescript_runs, {})
        expect.equal(world.notifications, { 'The command "shred" is unknown.' })
    end,

    a_url_without_a_command_runs_no_script_and_notifies = function()
        local world = open_url_of_command(start_trash_tool(), nil)
        expect.equal(world.applescript_runs, {})
        expect.equal(world.notifications, { 'The command "nil" is unknown.' })
    end,

    each_script_of_a_command_is_a_file_of_the_folder_of_the_controller = function()
        local world = start_trash_tool()
        open_url_of_command(world, "trash")
        open_url_of_command(world, "empty-trash")
        for _, path in ipairs(world.applescript_runs) do
            local file = expect.present(io.open(path, "r"), path)
            file:close()
        end
    end,
}
