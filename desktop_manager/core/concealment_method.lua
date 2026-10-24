local enumeration = require("desktop_manager.core.enumeration")

---The ways of taking the windows of the other profiles out of sight on a switch.
---`MINIMIZE_WINDOWS` minimizes each window, which puts it in the Dock.
---`HIDE_APPLICATIONS` hides an application whose windows all belong to other profiles, and
---minimizes the windows of the other profiles in any other application.
local concealment_method = enumeration.define({
    MINIMIZE_WINDOWS = "minimize_windows",
    HIDE_APPLICATIONS = "hide_applications",
})

---@alias ConcealmentMethod "minimize_windows"|"hide_applications"

return concealment_method
