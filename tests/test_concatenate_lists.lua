local concatenate_lists = require("desktop_manager.core.concatenate_lists")
local expect = require("tests.expect")

return {
    the_items_keep_the_order_of_the_lists_and_the_inputs_stay = function()
        local first = { "a", "b" }
        local joined = concatenate_lists.concatenate(first, {}, { "c" }, { "d", "e" })
        expect.equal(joined, { "a", "b", "c", "d", "e" })
        expect.equal(first, { "a", "b" })
    end,
}
