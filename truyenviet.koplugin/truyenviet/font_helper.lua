local DataStorage = require("datastorage")
local Font = require("ui/font")
local FontList = require("fontlist")
local ffiutil = require("ffi/util")
local util = require("util")

local FontHelper = {
    _initialized = false
}

function FontHelper:setupComicFont()
    if self._initialized then return end
    self._initialized = true

    pcall(function()
        local data_dir = DataStorage:getDataDir()
        local plugin_font = ffiutil.joinPath(data_dir, "plugins/truyenviet.koplugin/fonts/ComicHelvetic-Light.ttf")

        local primary_target = ffiutil.joinPath(data_dir, "fonts/ComicHelvetic-Light.ttf")

        -- 1. Sao chép font vào thư mục fonts nếu chưa có
        local f_check = io.open(primary_target, "rb")
        if f_check then
            f_check:close()
        else
            local f_in = io.open(plugin_font, "rb")
            if f_in then
                local data = f_in:read("*all")
                f_in:close()
                util.makePath(ffiutil.joinPath(data_dir, "fonts"))
                local f_out = io.open(primary_target, "wb")
                if f_out then
                    f_out:write(data)
                    f_out:close()
                end
            end
        end

        -- 2. Đăng ký với FontList của KOReader
        if FontList and FontList.fontinfo then
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

        -- 3. Cấu hình Font.fontmap của KOReader
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
