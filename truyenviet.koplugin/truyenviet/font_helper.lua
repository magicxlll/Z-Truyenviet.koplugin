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
        local user_font_dir = ffiutil.joinPath(data_dir, "fonts")
        local user_font = ffiutil.joinPath(user_font_dir, "ComicHelvetic-Light.ttf")

        -- 1. Sao chép font vào thư mục fonts của KOReader nếu chưa có
        local f_check = io.open(user_font, "rb")
        if f_check then
            f_check:close()
        else
            local f_in = io.open(plugin_font, "rb")
            if f_in then
                local data = f_in:read("*all")
                f_in:close()
                util.makePath(user_font_dir)
                local f_out = io.open(user_font, "wb")
                if f_out then
                    f_out:write(data)
                    f_out:close()
                end
            end
        end

        -- 2. Đăng ký ComicHelvetic-Light vào FontList và Font.fontmap của KOReader
        if FontList then
            FontList.fontinfo["ComicHelvetic-Light.ttf"] = {
                {
                    family = "ComicHelvetic-Light",
                    name = "ComicHelvetic-Light",
                    path = user_font,
                }
            }
            if not util.tableContains(FontList.fontlist, "ComicHelvetic-Light.ttf") then
                table.insert(FontList.fontlist, "ComicHelvetic-Light.ttf")
            end
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
end

return FontHelper
