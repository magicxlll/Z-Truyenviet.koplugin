local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

-- Mocks
package.preload["socket"] = function()
    return {
        gettime = function() return 0 end,
    }
end

package.preload["socket.http"] = function()
    return {
        request = function() return "OK", 200 end,
    }
end

package.preload["socket.url"] = function()
    return {
        escape = function(s) return s end,
        unescape = function(s) return s end,
    }
end

package.preload["ltn12"] = function()
    return {
        sink = {
            table = function() return function() end end,
        },
        source = {
            string = function() return function() end end,
        },
    }
end

package.preload["dispatcher"] = function()
    return {
        registerAction = function() end,
    }
end

package.preload["ui/widget/container/widgetcontainer"] = function()
    local WidgetContainer = {}
    function WidgetContainer:extend(def) return def end
    return WidgetContainer
end

local shown_dialogs = {}
package.preload["ui/uimanager"] = function()
    return {
        nextTick = function(_, cb) if cb then cb() end end,
        scheduleIn = function(_, _, cb) if cb then cb() end end,
        show = function(_, widget) table.insert(shown_dialogs, widget) end,
        close = function() end,
        forceRePaint = function() end,
    }
end

package.preload["ui/widget/confirmbox"] = function()
    return {
        new = function(_, def) return def end,
    }
end

package.preload["ui/widget/infomessage"] = function()
    return {
        new = function(_, def) return def end,
    }
end

package.preload["ui/widget/notification"] = function()
    return {
        new = function(_, def) return def end,
    }
end

package.preload["ui/network/networkmgr"] = function()
    return {
        isOnline = function() return true end,
        runWhenOnline = function(_, cb) if cb then cb() end end,
    }
end

package.preload["ui/trapper"] = function()
    return {
        wrap = function(_, cb) if cb then cb() end end,
    }
end

local settings_store = {}
package.preload["luasettings"] = function()
    return {
        open = function()
            return {
                readSetting = function(_, key, default)
                    if settings_store[key] ~= nil then return settings_store[key] end
                    return default
                end,
                saveSetting = function(_, key, val)
                    settings_store[key] = val
                end,
                flush = function() end,
            }
        end,
    }
end

package.preload["datastorage"] = function()
    return {
        getDataDir = function() return "/tmp/koreader" end,
        getFullDataDir = function() return "/tmp/koreader" end,
        getSettingsDir = function() return "/tmp/koreader/settings" end,
    }
end

package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function() return { mode = "directory" } end,
        mkdir = function() return true end,
        dir = function()
            return coroutine.wrap(function() end)
        end,
    }
end

package.preload["util"] = function()
    return {
        tableToPath = function() end,
        makePath = function() return true end,
        splitFilePath = function(_, path)
            return path:match("^(.*)/(.-)$")
        end,
    }
end

package.preload["ffi/util"] = function()
    return {
        joinPath = function(a, b, c)
            if c then return a .. "/" .. b .. "/" .. c end
            return a .. "/" .. b
        end,
    }
end

local Updater = require("truyenviet/updater")
local Storage = require("truyenviet/storage")
local Http = require("truyenviet/http_client")

local assertions = 0
local function assert_eq(a, b, msg)
    assertions = assertions + 1
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)))
    end
end

-- 1. Test Version Parsing
local v1 = Updater:parseVersion("3.10.0 (BUILD-1370)")
assert_eq(v1.major, 3, "v1 major")
assert_eq(v1.minor, 10, "v1 minor")
assert_eq(v1.patch, 0, "v1 patch")
assert_eq(v1.build, 1370, "v1 build")

local v2 = Updater:parseVersion("v3.9.4")
assert_eq(v2.major, 3, "v2 major")
assert_eq(v2.minor, 9, "v2 minor")
assert_eq(v2.patch, 4, "v2 patch")
assert_eq(v2.build, 0, "v2 build")

local v3 = Updater:parseVersion("4.0.1 (BUILD-1450)")
assert_eq(v3.major, 4, "v3 major")
assert_eq(v3.minor, 0, "v3 minor")
assert_eq(v3.patch, 1, "v3 patch")
assert_eq(v3.build, 1450, "v3 build")

-- 2. Test Version Comparison (isNewer)
assert_eq(Updater:isNewer("4.0.0", "3.10.0 (BUILD-1370)"), true, "4.0.0 > 3.10.0")
assert_eq(Updater:isNewer("3.11.0", "3.10.0 (BUILD-1370)"), true, "3.11.0 > 3.10.0")
assert_eq(Updater:isNewer("3.10.1", "3.10.0 (BUILD-1370)"), true, "3.10.1 > 3.10.0")
assert_eq(Updater:isNewer("3.10.0 (BUILD-1371)", "3.10.0 (BUILD-1370)"), true, "build 1371 > 1370")
assert_eq(Updater:isNewer("3.10.0 (BUILD-1370)", "3.10.0 (BUILD-1370)"), false, "equal versions")
assert_eq(Updater:isNewer("3.9.4", "3.10.0 (BUILD-1370)"), false, "3.9.4 < 3.10.0")
assert_eq(Updater:isNewer("2.0.0", "3.10.0 (BUILD-1370)"), false, "2.0.0 < 3.10.0")
assert_eq(Updater:isNewer("3.10.0 (BUILD-1369)", "3.10.0 (BUILD-1370)"), false, "build 1369 < 1370")

-- 3. Test Changelog Extraction
local sample_cl = [[
## 3.10.0 (BUILD-1370) - 2026-10-07

### Features
- Tích hợp tải Google Drive
- Fix test suites

## 3.8.0 (BUILD-1368) - 2026-08-09
- Cũ hơn
]]

local summary = Updater:extractChangelogSummary(sample_cl, "3.10.0")
assert_eq(summary:find("Tích hợp tải Google Drive") ~= nil, true, "Changelog contains Google Drive feature")
assert_eq(summary:find("Cũ hơn") == nil, true, "Changelog excludes older versions")

-- 4. Test Storage OTA Settings
Storage.settings = {
    readSetting = function(_, key, default)
        if settings_store[key] ~= nil then return settings_store[key] end
        return default
    end,
    saveSetting = function(_, key, val)
        settings_store[key] = val
    end,
    flush = function() end,
}

assert_eq(Storage:isAutoUpdateCheckEnabled(), true, "Default auto check is true")
Storage:setAutoUpdateCheckEnabled(false)
assert_eq(Storage:isAutoUpdateCheckEnabled(), false, "Auto check set to false")
Storage:setAutoUpdateCheckEnabled(true)
assert_eq(Storage:isAutoUpdateCheckEnabled(), true, "Auto check set back to true")

assert_eq(Storage:getUpdateCheckFrequency(), 86400, "Default check freq is 86400s")
Storage:setUpdateCheckFrequency(604800)
assert_eq(Storage:getUpdateCheckFrequency(), 604800, "Check freq updated to 604800s")

assert_eq(Storage:getIgnoredUpdateVersion(), "", "Default ignored version is empty")
Storage:setIgnoredUpdateVersion("3.10.1")
assert_eq(Storage:getIgnoredUpdateVersion(), "3.10.1", "Ignored version saved")

-- 5. Test Check For Update with mocked HTTP
local orig_http_get = Http.get

-- Case A: Remote has newer version
Http.get = function(_, url)
    if url == Updater.RAW_VERSION_URL then
        return 'return "3.11.0 (BUILD-1375)"'
    elseif url == Updater.RAW_CHANGELOG_URL then
        return sample_cl
    end
    return nil
end

local check_has_update, check_info
Updater:checkForUpdate(function(has_up, info, err)
    check_has_update = has_up
    check_info = info
end)
assert_eq(check_has_update, true, "Check detects newer version 3.11.0")
assert_eq(check_info.latest_version, "3.11.0 (BUILD-1375)", "Check info contains new version string")

-- Case B: Remote has same version
Http.get = function(_, url)
    if url == Updater.RAW_VERSION_URL then
        return 'return "3.10.0 (BUILD-1370)"'
    end
    return nil
end

local check_same_update
Updater:checkForUpdate(function(has_up)
    check_same_update = has_up
end)
assert_eq(check_same_update, false, "Check detects same version, no update needed")

-- 6. Test downloadAndInstall validation (rejects invalid payload)
Http.get = function(_, url)
    return "<html>Error 404 Not Found</html>"
end

local dl_ok, dl_err = Updater:downloadAndInstall("https://dummy.url/file.zip")
assert_eq(dl_ok, false, "downloadAndInstall rejects invalid non-zip payload")
assert_eq(dl_err:find("không hợp lệ") ~= nil or dl_err:find("quá nhỏ") ~= nil, true, "downloadAndInstall returns descriptive error")

-- Restore Http.get
Http.get = orig_http_get

print(string.format("Updater tests passed: %d assertions", assertions))
