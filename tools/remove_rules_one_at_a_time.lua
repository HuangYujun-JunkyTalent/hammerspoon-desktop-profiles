---Removes one rule of the code at a time from a copy of the tree and lists the tests that fail.
---A rule is a set of edits that turns the code into a version without the rule.
---A rule whose removal fails no test is a rule that no test checks.
---Run it from the repository root:
---  lua tools/remove_rules_one_at_a_time.lua <rules file> [word ...]
---The rules file is a Lua file that returns a list of rules.
---Each rule has a `name` and a list of `edits`.
---Each edit has a `path` relative to the repository, the `old` text and the `new` text.
---With words, the script runs only the rules whose names hold one of the words.
---Each rule runs in its own copy of the tree under a temporary folder, which the script removes
---afterwards, so no file of the repository changes.
---The script exits with status 1 in four cases:
---the unmodified copy fails a test, a rule's `old` text is not found exactly once, the tests of a
---rule do not run, or no test fails for a rule.
local SCRIPT_PATH = "tools/remove_rules_one_at_a_time.lua"
local USAGE = "lua " .. SCRIPT_PATH .. " <rules file> [word ...]"
local REPOSITORY_PATH_PATTERN = "/?tools/remove_rules_one_at_a_time%.lua$"
local LEFT_OUT_OF_COPY = { ".git", "node_modules", "asyar-*" }

local repository_folder = arg[0]:gsub(REPOSITORY_PATH_PATTERN, "")
if repository_folder == "" then
    repository_folder = "."
end
local lua_command = arg[-1] or "lua"

---@class Edit
---@field path string relative to the repository
---@field old string the text to replace, found exactly once as plain text
---@field new string

---@class Rule
---@field name string
---@field edits Edit[]

---@param text string
---@return string
local function quote_for_shell(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

---@param command string
---@return string output
---@return boolean is_successful
local function run_command(command)
    local process = io.popen(command .. " 2>&1")
    if not process then
        error(string.format("the command cannot start: %s", command), 0)
    end
    local output = process:read("a")
    local is_successful = process:close()
    return output, is_successful == true
end

---@param rules_path string
---@return Rule[]
local function load_rules(rules_path)
    local rules = dofile(rules_path)
    if type(rules) ~= "table" then
        error(string.format("%s must return a list of rules", rules_path), 0)
    end
    for index, rule in ipairs(rules) do
        if type(rule.name) ~= "string" or type(rule.edits) ~= "table" or #rule.edits == 0 then
            error(
                string.format("rule %d of %s needs a name and a list of edits", index, rules_path),
                0
            )
        end
        for _, edit in ipairs(rule.edits) do
            if type(edit.path) ~= "string" or type(edit.old) ~= "string" or edit.old == "" then
                error(
                    string.format(
                        "an edit of rule %s needs a path and a non-empty old text",
                        rule.name
                    ),
                    0
                )
            end
            if type(edit.new) ~= "string" then
                error(string.format("an edit of rule %s needs a new text", rule.name), 0)
            end
            if edit.path:match("^/") or ("/" .. edit.path .. "/"):find("/../", 1, true) then
                error(
                    string.format(
                        "the path %s of rule %s leaves the repository",
                        edit.path,
                        rule.name
                    ),
                    0
                )
            end
        end
    end
    return rules
end

---@param rules Rule[]
---@param words string[]
---@return Rule[]
local function select_rules(rules, words)
    if #words == 0 then
        return rules
    end
    local selected = {}
    for _, rule in ipairs(rules) do
        for _, word in ipairs(words) do
            if rule.name:find(word, 1, true) then
                table.insert(selected, rule)
                break
            end
        end
    end
    return selected
end

---@param text string
---@param piece string
---@return integer the number of places where the piece starts, as plain text, overlaps included
local function count_occurrences(text, piece)
    local count = 0
    local position = 1
    while true do
        local first = text:find(piece, position, true)
        if not first then
            return count
        end
        count = count + 1
        position = first + 1
    end
end

---@param path string
---@return string|nil content the content of the file, or nil when the file cannot be opened
local function read_file(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local content = file:read("a")
    file:close()
    return content
end

---@param path string
---@param content string
local function write_file(path, content)
    local file, open_error = io.open(path, "wb")
    if not file then
        error(string.format("%s cannot be written: %s", path, tostring(open_error)), 0)
    end
    file:write(content)
    file:close()
end

---@return string the folder of a new copy of the tree, which the caller removes
local function make_copy()
    local folder_output, is_made = run_command("mktemp -d")
    local folder = folder_output:gsub("%s+$", "")
    if not is_made or folder == "" then
        error("the temporary folder cannot be made: " .. folder_output, 0)
    end
    local excludes = {}
    for _, pattern in ipairs(LEFT_OUT_OF_COPY) do
        table.insert(excludes, "--exclude=" .. quote_for_shell(pattern))
    end
    local output, is_copied = run_command(
        string.format(
            "rsync -a %s %s %s",
            table.concat(excludes, " "),
            quote_for_shell(repository_folder .. "/"),
            quote_for_shell(folder .. "/")
        )
    )
    if not is_copied then
        run_command("rm -rf " .. quote_for_shell(folder))
        error("the tree cannot be copied: " .. output, 0)
    end
    return folder
end

---@param folder string
---@return string[] the module and case of each failed test
---@return boolean did_tests_run false when the tests ended without the summary line
---@return string output
local function run_tests(folder)
    local output = run_command(
        string.format("cd %s && %s tests/run_tests.lua", quote_for_shell(folder), lua_command)
    )
    local failed = {}
    for module_name, case_name in ("\n" .. output):gmatch("\nFAIL%s+([^:\n]+): ([^:\n]+):") do
        table.insert(failed, module_name .. ": " .. case_name)
    end
    local did_tests_run = output:match("%d+ failed\n$") ~= nil
    return failed, did_tests_run, output
end

---@param rule Rule
---@param folder string the copy that the rule changes
---@return string|nil problem the first edit whose file is missing or whose old text is not found
---exactly once
local function apply_rule(rule, folder)
    for _, edit in ipairs(rule.edits) do
        local path = folder .. "/" .. edit.path
        local content = read_file(path)
        if not content then
            return string.format("the file %s does not exist", edit.path)
        end
        local count = count_occurrences(content, edit.old)
        if count ~= 1 then
            return string.format("the old text is found %d times in %s, not once", count, edit.path)
        end
        local first, last = content:find(edit.old, 1, true)
        write_file(path, content:sub(1, first - 1) .. edit.new .. content:sub(last + 1))
    end
    return nil
end

---The outcomes of a rule.
local CAUGHT = "caught"
local NOT_CAUGHT = "not caught"
local NOT_RUN = "not run"

---Runs one rule in its own copy and removes the copy.
---@param rule Rule
---@return string line the result for the rule
---@return string outcome CAUGHT, NOT_CAUGHT or NOT_RUN
local function run_rule(rule)
    local folder = make_copy()
    local is_run, line, outcome = pcall(function()
        local problem = apply_rule(rule, folder)
        if problem then
            return string.format("%s: not run, %s", rule.name, problem), NOT_RUN
        end
        local failed, did_tests_run, output = run_tests(folder)
        if not did_tests_run then
            local last_line = output:gsub("%s+$", ""):match("[^\n]*$")
            return string.format("%s: the tests did not run: %s", rule.name, last_line), NOT_RUN
        end
        if #failed == 0 then
            return string.format("%s: no test fails", rule.name), NOT_CAUGHT
        end
        return string.format("%s: %d failed: %s", rule.name, #failed, table.concat(failed, ", ")),
            CAUGHT
    end)
    run_command("rm -rf " .. quote_for_shell(folder))
    if not is_run then
        return string.format("%s: not run, %s", rule.name, tostring(line)), NOT_RUN
    end
    return line, outcome
end

local rules_path = arg[1]
if not rules_path then
    error("the rules file is missing: " .. USAGE, 0)
end
local words = {}
for index = 2, #arg do
    table.insert(words, arg[index])
end
local rules = select_rules(load_rules(rules_path), words)
if #rules == 0 then
    error("no rule matches the words: " .. USAGE, 0)
end

local baseline_folder = make_copy()
local baseline_failed, did_baseline_run, baseline_output = run_tests(baseline_folder)
run_command("rm -rf " .. quote_for_shell(baseline_folder))
if not did_baseline_run or #baseline_failed > 0 then
    print("the unmodified copy does not pass its tests, so no rule ran:")
    print(baseline_output)
    os.exit(1)
end

local counts = { [CAUGHT] = 0, [NOT_CAUGHT] = 0, [NOT_RUN] = 0 }
for _, rule in ipairs(rules) do
    local line, outcome = run_rule(rule)
    print(line)
    counts[outcome] = counts[outcome] + 1
end
print(
    string.format(
        "%d rules: %d caught, %d not caught by any test, %d not run",
        #rules,
        counts[CAUGHT],
        counts[NOT_CAUGHT],
        counts[NOT_RUN]
    )
)
os.exit(counts[CAUGHT] == #rules and 0 or 1)
