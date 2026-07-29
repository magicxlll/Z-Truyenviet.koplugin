local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

package.preload["dispatcher"] = function()
    return {
        registerAction = function() end,
    }
end

package.preload["ui/widget/container/widgetcontainer"] = function()
    local WidgetContainer = {}
    function WidgetContainer:extend(definition)
        return definition
    end
    return WidgetContainer
end

package.preload["truyenviet/browser"] = function()
    return {
        showRoot = function() end,
    }
end

package.preload["truyenviet/reader"] = function()
    return {}
end

package.preload["truyenviet/version"] = function()
    return "test"
end

local Plugin = require("main")
local menu_items = {}

Plugin.addToMainMenu({
    ui = {
        name = "ReaderUI",
    },
}, menu_items)

local reader_item = assert(
    menu_items.truyenviet_reader_tools,
    "ReaderUI menu item was not registered"
)

assert(
    reader_item.sorting_hint == "tools",
    string.format(
        "ReaderUI sorting_hint must target KOReader's 'tools' menu, got %s",
        tostring(reader_item.sorting_hint)
    )
)

print("Main menu tests passed")
