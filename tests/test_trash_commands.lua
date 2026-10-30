local expect = require("tests.expect")
local trash_commands = require("trash.core.trash_commands")

local EMPTY_TRASH = trash_commands.BY_ID["empty-trash"]

---@return string[] the ids of the commands of `asyar-trash/manifest.json`, in order
local function list_manifest_command_ids()
    local file = expect.present(io.open("asyar-trash/manifest.json", "r"), "the manifest")
    local text = file:read("a")
    file:close()
    local commands = expect.present(text:match('"commands"%s*:%s*(%b[])'), "a list of commands")
    local ids = {}
    for id in commands:gmatch('"id"%s*:%s*"([^"]+)"') do
        table.insert(ids, id)
    end
    return ids
end

return {
    every_command_of_the_manifest_has_a_script_and_the_title_of_its_item = function()
        local ids = list_manifest_command_ids()
        expect.equal(ids, { "trash", "empty-trash" })
        expect.equal(trash_commands.BY_ID.trash.title, "Trash")
        expect.equal(EMPTY_TRASH.title, "Empty Trash")
    end,

    the_error_of_osascript_is_read_without_the_path_of_the_script = function()
        local error_output = "/repository/trash/macos/open_trash.applescript:95:105: "
            .. "execution error: Finder got an error: Not authorized to send Apple events to "
            .. "Finder. (-1743)\n"
        expect.equal(
            trash_commands.read_osascript_error(error_output),
            "Finder got an error: Not authorized to send Apple events to Finder. (-1743)"
        )
    end,

    an_error_of_another_form_is_read_whole = function()
        expect.equal(
            trash_commands.read_osascript_error("  osascript: no such file\n"),
            "osascript: no such file"
        )
        expect.equal(
            trash_commands.read_osascript_error("\n"),
            "osascript failed without a message."
        )
    end,

    a_failed_script_is_a_notified_failure_under_the_title_of_its_command = function()
        local report =
            trash_commands.report_script_end(EMPTY_TRASH, 1, "", "x: execution error: e (1)")
        expect.equal(report, {
            title = "Empty Trash failed",
            message = "e (1)",
            is_failure = true,
            is_notified = true,
        })
    end,

    an_empty_trash_is_a_notified_result = function()
        expect.equal(trash_commands.report_script_end(EMPTY_TRASH, 0, "empty\n", ""), {
            title = "Empty Trash",
            message = "The Trash is empty.",
            is_failure = false,
            is_notified = true,
        })
    end,

    another_outcome_is_logged_alone = function()
        expect.equal(trash_commands.report_script_end(EMPTY_TRASH, 0, "cancelled\n", ""), {
            title = "Empty Trash",
            message = "cancelled",
            is_failure = false,
            is_notified = false,
        })
    end,
}
