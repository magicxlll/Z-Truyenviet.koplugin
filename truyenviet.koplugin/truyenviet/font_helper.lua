local DataStorage = require("datastorage")
local Font = require("ui/font")
local FontList = require("fontlist")
local ffiutil = require("ffi/util")
local util = require("util")

local FontHelper = {
    FONT_NAME = "BeVietnamPro-Regular.ttf",
    FONT_FAMILY = "Be Vietnam Pro",
    FONT_MEDIUM_NAME = "BeVietnamPro-Medium.ttf",
}

local function findPluginFont(filename)
    local candidate_paths = {}
    local info = debug.getinfo(1, "S")
    if info and info.source then
        local src = info.source:match("@?(.*)")
        local dir = src and src:match("^(.*)/[^/]+$")
        if dir then
            candidate_paths[#candidate_paths + 1] = ffiutil.joinPath(dir, "../fonts/" .. filename)
            candidate_paths[#candidate_paths + 1] = ffiutil.joinPath(dir, "fonts/" .. filename)
        end
    end
    local data_dir = DataStorage:getDataDir()
    candidate_paths[#candidate_paths + 1] = ffiutil.joinPath(data_dir, "plugins/truyenviet.koplugin/fonts/" .. filename)
    candidate_paths[#candidate_paths + 1] = ffiutil.joinPath("./plugins/truyenviet.koplugin/fonts/" .. filename)
    candidate_paths[#candidate_paths + 1] = ffiutil.joinPath("plugins/truyenviet.koplugin/fonts/" .. filename)
    candidate_paths[#candidate_paths + 1] = ffiutil.joinPath("fonts/" .. filename)

    for _, path in ipairs(candidate_paths) do
        local f = io.open(path, "rb")
        if f then
            local data = f:read("*all")
            f:close()
            if data and #data > 0 then
                return data, path
            end
        end
    end
    return nil
end

function FontHelper:setupFont()
    if self._setup_done then return end
    self._setup_done = true

    pcall(function()
        local data_dir = DataStorage:getDataDir()
        local fonts_to_install = {
            { file = self.FONT_NAME, family = self.FONT_FAMILY, name = "BeVietnamPro-Regular" },
            { file = self.FONT_MEDIUM_NAME, family = self.FONT_FAMILY, name = "BeVietnamPro-Medium" },
        }

        local target_dirs = {
            ffiutil.joinPath(data_dir, "fonts"),
        }
        local extra_dirs = {
            "./fonts",
            "/opt/lib/koreader/fonts",
            "/mnt/onboard/fonts",
            "/sdcard/fonts",
        }
        for _, dir in ipairs(extra_dirs) do
            local parent = dir:match("^(.*)/[^/]+$")
            if parent then
                local f = io.open(parent, "r")
                if f then
                    f:close()
                    table.insert(target_dirs, dir)
                end
            end
        end

        for _, font_item in ipairs(fonts_to_install) do
            local font_data = findPluginFont(font_item.file)
            if font_data then
                for _, dir in ipairs(target_dirs) do
                    pcall(function()
                        util.makePath(dir)
                        local dest_path = ffiutil.joinPath(dir, font_item.file)
                        local f_out = io.open(dest_path, "wb")
                        if f_out then
                            f_out:write(font_data)
                            f_out:close()
                        end
                    end)
                end
            end
        end

        -- Đăng ký với FontList của KOReader
        if FontList and FontList.fontinfo then
            local primary_target = ffiutil.joinPath(data_dir, "fonts/" .. self.FONT_NAME)
            local entry = {
                {
                    family = self.FONT_FAMILY,
                    name = "BeVietnamPro-Regular",
                    path = primary_target,
                }
            }
            FontList.fontinfo[self.FONT_NAME] = entry
            FontList.fontinfo["BeVietnamPro-Regular"] = entry
            FontList.fontinfo[self.FONT_FAMILY] = entry

            -- Chuyển hướng các alias cũ để sửa lỗi font ngay lập tức nếu từng kích hoạt
            FontList.fontinfo["ComicHelvetic-Light.ttf"] = entry
            FontList.fontinfo["ComicHelvetic-Light"] = entry
            FontList.fontinfo["Comic Helvetic"] = entry

            if FontList.fontnames then
                FontList.fontnames[self.FONT_FAMILY] = entry
                FontList.fontnames["BeVietnamPro-Regular"] = entry
                FontList.fontnames[self.FONT_NAME] = entry
                FontList.fontnames["Comic Helvetic"] = entry
                FontList.fontnames["ComicHelvetic-Light"] = entry
                FontList.fontnames["ComicHelvetic-Light.ttf"] = entry
            end
            if FontList.fontlist and not util.tableContains(FontList.fontlist, self.FONT_NAME) then
                table.insert(FontList.fontlist, self.FONT_NAME)
            end
        end

        -- Tự động nâng cấp patch cũ nếu user đã từng cài bản ComicHelvetic lỗi font
        self:autoUpgradeOldPatch()
    end)
end

-- Backward compatibility alias
function FontHelper:setupComicFont()
    self:setupFont()
end

function FontHelper:autoUpgradeOldPatch()
    pcall(function()
        local data_dir = DataStorage:getDataDir()
        local patch_file = ffiutil.joinPath(data_dir, "patches/2--ui-font.lua")
        local f = io.open(patch_file, "r")
        if f then
            local content = f:read("*all")
            f:close()
            if content and content:find("ComicHelvetic") then
                self:installUserPatch()
            end
        end
    end)
end

function FontHelper:installUserPatch()
    self:setupFont()
    local data_dir = DataStorage:getDataDir()
    local patches_dir = ffiutil.joinPath(data_dir, "patches")
    util.makePath(patches_dir)

    local patch_file = ffiutil.joinPath(patches_dir, "2--ui-font.lua")
    local patch_content = [[
-- KOReader User Patch for Be Vietnam Pro UI Font (Created by Truyện Việt)
local Font = require("ui/font")
local FontList = require("fontlist")

pcall(function()
    local DataStorage = require("datastorage")
    local ffiutil = require("ffi/util")
    local font_path = ffiutil.joinPath(DataStorage:getDataDir(), "fonts/BeVietnamPro-Regular.ttf")

    if FontList and FontList.fontinfo then
        local entry = {
            {
                family = "Be Vietnam Pro",
                name = "BeVietnamPro-Regular",
                path = font_path,
            }
        }
        FontList.fontinfo["BeVietnamPro-Regular.ttf"] = entry
        FontList.fontinfo["BeVietnamPro-Regular"] = entry
        FontList.fontinfo["Be Vietnam Pro"] = entry
        -- Chuyển hướng ComicHelvetic sang Be Vietnam Pro để khắc phục lỗi font tiếng Việt
        FontList.fontinfo["ComicHelvetic-Light.ttf"] = entry
        FontList.fontinfo["ComicHelvetic-Light"] = entry
        FontList.fontinfo["Comic Helvetic"] = entry
    end

    if Font and Font.fontmap then
        Font.fontmap.cfont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.infofont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.smallinfofont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.xx_smallinfofont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.tfont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.smalltfont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.x_smalltfont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.ffont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.smallffont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.largeffont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.rifont = "BeVietnamPro-Regular.ttf"
        Font.fontmap.pgfont = "BeVietnamPro-Regular.ttf"
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
    pcall(function() self:setupFont() end)
    local data_dir = DataStorage:getDataDir()
    local primary_target = ffiutil.joinPath(data_dir, "fonts/" .. self.FONT_NAME)
    local ok, face = pcall(Font.getFace, Font, primary_target, size)
    if ok and face then
        return face
    end
    ok, face = pcall(Font.getFace, Font, self.FONT_NAME, size)
    if ok and face then
        return face
    end
    return Font:getFace(alias or "infofont", size)
end

return FontHelper
