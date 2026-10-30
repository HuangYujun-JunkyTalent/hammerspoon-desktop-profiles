local expect = require("tests.expect")

---@return string[] the module names of every Lua file under desktop_manager, keyboard_shortcuts,
---window_tiling and trash
local function list_module_names()
    local listing =
        io.popen('find desktop_manager keyboard_shortcuts window_tiling trash -name "*.lua"')
    if not listing then
        error("the folders of the modules cannot be listed")
    end
    local names = {}
    for path in listing:lines() do
        table.insert(names, (path:gsub("%.lua$", ""):gsub("/", ".")))
    end
    listing:close()
    table.sort(names)
    return names
end

return {
    every_module_loads_without_calling_hammerspoon = function()
        local names = list_module_names()
        expect.equal(#names > 20, true)
        for _, name in ipairs(names) do
            local is_loaded, message = pcall(require, name)
            if not is_loaded then
                error(string.format("%s did not load: %s", name, tostring(message)), 0)
            end
        end
    end,
}
