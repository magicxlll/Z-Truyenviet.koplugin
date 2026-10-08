local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

local mock_data_dir = "/tmp/truyenviet_font_test"
os.execute("rm -rf " .. mock_data_dir)
os.execute("mkdir -p " .. mock_data_dir .. "/fonts " .. mock_data_dir .. "/patches")

package.preload["datastorage"] = function()
    return {
        getDataDir = function() return mock_data_dir end,
    }
end

local mock_fontmap = {}
local mock_fontinfo = {}
local mock_fontnames = {}
local mock_fontlist = {}

package.preload["ui/font"] = function()
    return {
        fontmap = mock_fontmap,
        getFace = function(_self, name, size)
            return { name = name, size = size }
        end,
    }
end

package.preload["fontlist"] = function()
    return {
        fontinfo = mock_fontinfo,
        fontnames = mock_fontnames,
        fontlist = mock_fontlist,
    }
end

package.preload["ffi/util"] = function()
    return {
        joinPath = function(...)
            local parts = {...}
            return table.concat(parts, "/"):gsub("/+", "/")
        end,
    }
end

package.preload["util"] = function()
    return {
        makePath = function(path)
            if path:find("^/tmp") or path:find("^%./") then
                os.execute("mkdir -p " .. path .. " 2>/dev/null")
            end
            return true
        end,
        tableContains = function(t, val)
            for _, v in ipairs(t) do
                if v == val then return true end
            end
            return false
        end,
    }
end

local FontHelper = require("truyenviet/font_helper")

assert(FontHelper.FONT_NAME == "BeVietnamPro-Regular.ttf", "Font name must be BeVietnamPro-Regular.ttf")
assert(FontHelper.FONT_FAMILY == "Be Vietnam Pro", "Font family must be Be Vietnam Pro")

-- 1. Test setupFont()
FontHelper:setupFont()
assert(mock_fontinfo["BeVietnamPro-Regular.ttf"] ~= nil, "FontList must register BeVietnamPro-Regular.ttf")
assert(mock_fontinfo["ComicHelvetic-Light.ttf"] ~= nil, "ComicHelvetic alias must point to safe font")

-- 2. Test installUserPatch()
local ok = FontHelper:installUserPatch()
assert(ok == true, "installUserPatch should succeed")
assert(FontHelper:isUserPatchInstalled() == true, "Patch should be reported as installed")

local patch_path = mock_data_dir .. "/patches/2--ui-font.lua"
local f = io.open(patch_path, "r")
assert(f ~= nil, "Patch file must exist")
local content = f:read("*all")
f:close()

assert(content:find("BeVietnamPro%-Regular%.ttf"), "Patch must map to BeVietnamPro-Regular.ttf")
assert(content:find("infofont = \"BeVietnamPro%-Regular%.ttf\""), "Patch must map infofont")

-- 3. Test autoUpgradeOldPatch()
-- Simulate legacy ComicHelvetic patch
local f_legacy = io.open(patch_path, "w")
f_legacy:write("-- Old patch with ComicHelvetic-Light.ttf\nFont.fontmap.infofont = 'ComicHelvetic-Light.ttf'")
f_legacy:close()

FontHelper:autoUpgradeOldPatch()
local f_check = io.open(patch_path, "r")
local upgraded_content = f_check:read("*all")
f_check:close()
assert(upgraded_content:find("BeVietnamPro%-Regular%.ttf"), "Legacy patch must be auto-upgraded to Be Vietnam Pro")

-- 4. Test removeUserPatch()
FontHelper:removeUserPatch()
assert(FontHelper:isUserPatchInstalled() == false, "Patch should be removed")

-- 5. Test getFace()
local face = FontHelper:getFace("smallinfofont", 18)
assert(face ~= nil, "getFace should return a face")
assert(face.name:find("BeVietnamPro") or face.name == "smallinfofont", "Face name should resolve correctly")

-- Cleanup
os.execute("rm -rf " .. mock_data_dir)

print("FontHelper tests passed successfully!")
