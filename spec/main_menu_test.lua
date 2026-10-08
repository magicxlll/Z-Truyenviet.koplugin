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

local browser_show_root_called = false
package.preload["truyenviet/browser"] = function()
    return {
        showRoot = function()
            browser_show_root_called = true
        end,
    }
end

package.preload["truyenviet/reader"] = function()
    return {}
end

package.preload["truyenviet/version"] = function()
    return "3.12.0"
end

package.preload["truyenviet/font_helper"] = function()
    return {
        setupFont = function() end,
    }
end

package.preload["truyenviet/updater"] = function()
    return {
        scheduleBackgroundCheck = function() end,
    }
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

-- Title must be clean "Truyện Việt" without emoji so it sorts under T
assert(reader_item.text == "Truyện Việt", "Menu text must be clean 'Truyện Việt'")
assert(type(reader_item.callback) == "function", "Menu item must provide callback for 1-tap launch")

local found_gdrive = false
for _, item in ipairs(reader_item.sub_item_table or {}) do
    if item.text and item.text:find("Google Drive") then
        found_gdrive = true
        break
    end
end
assert(found_gdrive, "Google Drive menu item not found in sub_item_table")
assert(type(Plugin.onTruyenVietGDriveDownload) == "function", "onTruyenVietGDriveDownload handler missing")

local found_ota = false
for _, item in ipairs(reader_item.sub_item_table or {}) do
    if item.text and item.text:find("OTA") then
        found_ota = true
        break
    end
end
assert(found_ota, "OTA Update menu item not found in sub_item_table")
assert(type(Plugin.onTruyenVietCheckUpdate) == "function", "onTruyenVietCheckUpdate handler missing")

-- ==================== ZenOS Compatibility Verification ====================
-- ZenOS checks LAUNCH_METHODS = { "onShow", "show", "open", "launch", "onOpen" }
-- and camel = "on" .. key:sub(1,1):upper() .. key:sub(2) -> "onTruyenviet"
local LAUNCH_METHODS = { "onShow", "show", "open", "launch", "onOpen" }
for _, method in ipairs(LAUNCH_METHODS) do
    assert(type(Plugin[method]) == "function", "Plugin must define launch method: " .. method)
end
assert(type(Plugin.onTruyenviet) == "function", "Plugin must define onTruyenviet method")

-- Test that executing onShow triggers browser:showRoot()
browser_show_root_called = false
Plugin:onShow()
assert(browser_show_root_called == true, "Plugin:onShow() must invoke Browser:showRoot()")

-- Test ZenOS scan method resolution
local function is_callable(v) return type(v) == "function" end
local function find_method(mod, key)
    for _i, method in ipairs(LAUNCH_METHODS) do
        if is_callable(mod[method]) then return method end
    end
    local camel = "on" .. key:sub(1, 1):upper() .. key:sub(2)
    if is_callable(mod[camel]) then return camel end
end

local zenos_detected_method = find_method(Plugin, "truyenviet")
assert(zenos_detected_method == "onShow", "ZenOS must discover onShow launch method")

-- Test alphabetical sorting under ZenOS "Choose plugin menu"
local plugin_titles = {
    "Auto frontlight", "Calibre", "Exporter", "Invert colors", "Kosync",
    "NewsDownloader", "Periodic timer", "ReadTimer", "SSH server",
    "Statistics", "System statistics", "Terminal", "Tweak document settings",
    "Wallabag",
}
table.insert(plugin_titles, reader_item.text) -- "Truyện Việt"
table.sort(plugin_titles, function(a, b) return a < b end)

-- Find position of "Truyện Việt"
local pos = 0
for i, title in ipairs(plugin_titles) do
    if title == "Truyện Việt" then
        pos = i
        break
    end
end

assert(plugin_titles[pos - 1] == "Terminal", "Truyện Việt must sort after Terminal")
assert(plugin_titles[pos + 1] == "Tweak document settings", "Truyện Việt must sort before Tweak document settings")

print("Main menu & ZenOS launcher compatibility tests passed!")
