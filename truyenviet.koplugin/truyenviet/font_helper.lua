local DataStorage = require("datastorage")
local Font = require("ui/font")
local FontList = require("fontlist")
local ffiutil = require("ffi/util")
local util = require("util")

local FontHelper = {
    _initialized = false
}

function FontHelper:setupComicFont()
    pcall(function()
        local data_dir = DataStorage:getDataDir()
        local plugin_font = ffiutil.joinPath(data_dir, "plugins/truyenviet.koplugin/fonts/ComicHelvetic-Light.ttf")
        
        -- Các đường dẫn fonts của KOReader
        local target_dirs = {
            ffiutil.joinPath(data_dir, "fonts"),
            "./fonts",
            "/opt/lib/koreader/fonts",
        }

        local primary_target = ffiutil.joinPath(data_dir, "fonts/ComicHelvetic-Light.ttf")

        for _, dir in ipairs(target_dirs) do
            pcall(function()
                util.makePath(dir)
                local dest_path = ffiutil.joinPath(dir, "ComicHelvetic-Light.ttf")
                local f_check = io.open(dest_path, "rb")
                if f_check then
                    f_check:close()
                else
                    local f_in = io.open(plugin_font, "rb")
                    if f_in then
                        local data = f_in:read("*all")
                        f_in:close()
                        local f_out = io.open(dest_path, "wb")
                        if f_out then
                            f_out:write(data)
                            f_out:close()
                        end
                    end
                end
            end)
        end

        -- 2. Đăng ký ComicHelvetic-Light vào FontList và Font.fontmap của KOReader
        if FontList then
            FontList.fontinfo["ComicHelvetic-Light.ttf"] = {
                {
                    family = "ComicHelvetic-Light",
                    name = "ComicHelvetic-Light",
                    path = primary_target,
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
    self._initialized = true
end

function FontHelper:getFace(alias, size)
    if not self._initialized then
        self:setupComicFont()
    end
    local ok, face = pcall(Font.getFace, Font, "ComicHelvetic-Light.ttf", size)
    if ok and face then
        return face
    end
    return Font:getFace(alias or "infofont", size)
end

return FontHelper
