local DataStorage = require("datastorage")
local Font = require("ui/font")
local FontList = require("fontlist")
local ffiutil = require("ffi/util")
local util = require("util")

local FontHelper = {}

function FontHelper:setupComicFont()
    pcall(function()
        local data_dir = DataStorage:getDataDir()
        local plugin_font = ffiutil.joinPath(data_dir, "plugins/truyenviet.koplugin/fonts/ComicHelvetic-Light.ttf")

        local font_data = nil
        local f_in = io.open(plugin_font, "rb")
        if f_in then
            font_data = f_in:read("*all")
            f_in:close()
        end

        if not font_data then return end

        local target_dirs = {
            ffiutil.joinPath(data_dir, "fonts"),
            "./fonts",
            "/opt/lib/koreader/fonts",
            "/mnt/onboard/fonts",
            "/sdcard/fonts",
        }

        for _, dir in ipairs(target_dirs) do
            pcall(function()
                util.makePath(dir)
                local dest_path = ffiutil.joinPath(dir, "ComicHelvetic-Light.ttf")
                local f_out = io.open(dest_path, "wb")
                if f_out then
                    f_out:write(font_data)
                    f_out:close()
                end
            end)
        end

        -- 2. Đăng ký với FontList của KOReader
        if FontList and FontList.fontinfo then
            local primary_target = ffiutil.joinPath(data_dir, "fonts/ComicHelvetic-Light.ttf")
            local entry = {
                {
                    family = "Comic Helvetic",
                    name = "ComicHelvetic-Light",
                    path = primary_target,
                }
            }
            FontList.fontinfo["ComicHelvetic-Light.ttf"] = entry
            FontList.fontinfo["ComicHelvetic-Light"] = entry
            FontList.fontinfo["Comic Helvetic"] = entry
            if FontList.fontnames then
                FontList.fontnames["Comic Helvetic"] = entry
                FontList.fontnames["ComicHelvetic-Light"] = entry
                FontList.fontnames["ComicHelvetic-Light.ttf"] = entry
            end
            if FontList.fontlist and not util.tableContains(FontList.fontlist, "ComicHelvetic-Light.ttf") then
                table.insert(FontList.fontlist, "ComicHelvetic-Light.ttf")
            end
        end
    end)
end

function FontHelper:installUserPatch()
    self:setupComicFont()
    local data_dir = DataStorage:getDataDir()
    local patches_dir = ffiutil.joinPath(data_dir, "patches")
    util.makePath(patches_dir)

    local patch_file = ffiutil.joinPath(patches_dir, "2--ui-font.lua")
    local patch_content = [[
-- KOReader User Patch for ComicHelvetic UI Font (Created by Truyện Việt)
local Font = require("ui/font")
local FontList = require("fontlist")

pcall(function()
    local DataStorage = require("datastorage")
    local ffiutil = require("ffi/util")
    local font_path = ffiutil.joinPath(DataStorage:getDataDir(), "fonts/ComicHelvetic-Light.ttf")

    if FontList and FontList.fontinfo then
        local entry = {
            {
                family = "Comic Helvetic",
                name = "ComicHelvetic-Light",
                path = font_path,
            }
        }
        FontList.fontinfo["ComicHelvetic-Light.ttf"] = entry
        FontList.fontinfo["ComicHelvetic-Light"] = entry
        FontList.fontinfo["Comic Helvetic"] = entry
    end

    if Font and Font.fontmap then
        Font.fontmap.cfont = "ComicHelvetic-Light.ttf"
        Font.fontmap.infofont = "ComicHelvetic-Light.ttf"
        Font.fontmap.smallinfofont = "ComicHelvetic-Light.ttf"
        Font.fontmap.xx_smallinfofont = "ComicHelvetic-Light.ttf"
        Font.fontmap.tfont = "ComicHelvetic-Light.ttf"
        Font.fontmap.smalltfont = "ComicHelvetic-Light.ttf"
        Font.fontmap.x_smalltfont = "ComicHelvetic-Light.ttf"
        Font.fontmap.ffont = "ComicHelvetic-Light.ttf"
        Font.fontmap.smallffont = "ComicHelvetic-Light.ttf"
        Font.fontmap.largeffont = "ComicHelvetic-Light.ttf"
        Font.fontmap.rifont = "ComicHelvetic-Light.ttf"
        Font.fontmap.pgfont = "ComicHelvetic-Light.ttf"
    end
end)
]]

    local f = io.open(patch_file, "w")
    if f then
        f:write(patch_content)
        f:close()
        return true
    end
    return false
end

function FontHelper:removeUserPatch()
    local data_dir = DataStorage:getDataDir()
    local patch_file = ffiutil.joinPath(data_dir, "patches/2--ui-font.lua")
    os.remove(patch_file)
    return true
end

function FontHelper:isUserPatchInstalled()
    local data_dir = DataStorage:getDataDir()
    local patch_file = ffiutil.joinPath(data_dir, "patches/2--ui-font.lua")
    local f = io.open(patch_file, "r")
    if f then
        f:close()
        return true
    end
    return false
end

function FontHelper:getFace(alias, size)
    pcall(function() self:setupComicFont() end)
    local data_dir = DataStorage:getDataDir()
    local primary_target = ffiutil.joinPath(data_dir, "fonts/ComicHelvetic-Light.ttf")
    local ok, face = pcall(Font.getFace, Font, primary_target, size)
    if ok and face then
        return face
    end
    ok, face = pcall(Font.getFace, Font, "ComicHelvetic-Light.ttf", size)
    if ok and face then
        return face
    end
    return Font:getFace(alias or "infofont", size)
end

return FontHelper
