local repository_folder = arg[0]:gsub("/?tests/run_tests%.lua$", "")
if repository_folder == "" then
    repository_folder = "."
end
package.path = repository_folder .. "/?.lua;" .. package.path

---@return string[]
local function list_test_module_names()
    local tests_folder = repository_folder .. "/tests"
    local listing = io.popen(string.format('ls "%s"', tests_folder))
    if not listing then
        error(string.format("the folder %s cannot be listed", tests_folder))
    end
    local names = {}
    for file_name in listing:lines() do
        local module_name = file_name:match("^(test_.+)%.lua$")
        if module_name then
            table.insert(names, module_name)
        end
    end
    listing:close()
    table.sort(names)
    return names
end

---@param module_name string
---@return integer
local function run_test_module(module_name)
    local cases = require("tests." .. module_name)
    local case_names = {}
    for case_name in pairs(cases) do
        table.insert(case_names, case_name)
    end
    table.sort(case_names)
    local failure_count = 0
    for _, case_name in ipairs(case_names) do
        local is_successful, message = pcall(cases[case_name])
        if is_successful then
            print(string.format("ok    %s: %s", module_name, case_name))
        else
            failure_count = failure_count + 1
            print(string.format("FAIL  %s: %s: %s", module_name, case_name, tostring(message)))
        end
    end
    return failure_count
end

local failure_count = 0
for _, module_name in ipairs(list_test_module_names()) do
    failure_count = failure_count + run_test_module(module_name)
end
print(string.format("%d failed", failure_count))
os.exit(failure_count == 0 and 0 or 1)
