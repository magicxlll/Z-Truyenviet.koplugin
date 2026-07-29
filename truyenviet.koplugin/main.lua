local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Browser = require("truyenviet/browser")
local Reader = require("truyenviet/reader")
local Version = require("truyenviet/version")

local TruyenViet = WidgetContainer:extend{
    name = "truyenviet",
    is_doc_only = false,
    VERSION = Version,
}

function TruyenViet:init()
    -- Tự động cài đặt font mặc định ComicHelvetic-Light.ttf vào hệ thống KOReader nếu chưa có
    pcall(function()
        local DataStorage = require("datastorage")
        local ffiutil = require("ffi/util")
        local font_src = ffiutil.joinPath(DataStorage:getDataDir(), "plugins/truyenviet.koplugin/fonts/ComicHelvetic-Light.ttf")
        local font_dest_dir = ffiutil.joinPath(DataStorage:getDataDir(), "fonts")
        local font_dest = ffiutil.joinPath(font_dest_dir, "ComicHelvetic-Light.ttf")
        
        local f_dest = io.open(font_dest, "r")
        if f_dest then
            f_dest:close()
        else
            local f_src = io.open(font_src, "rb")
            if f_src then
                local content = f_src:read("*all")
                f_src:close()
                require("util").makePath(font_dest_dir)
                local f_out = io.open(font_dest, "wb")
                if f_out then
                    f_out:write(content)
                    f_out:close()
                end
            end
        end
    end)

    if self.ui.name == "ReaderUI" then
        Reader:initializeFromReaderUI(self.ui)
    end

    if self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    local UIManager = require("ui/uimanager")
    UIManager:nextTick(function()
        if self.ui.title_bar and not self._topbar_button_added then
            self._topbar_button_added = true
            if type(self.ui.title_bar.addButton) == "function" then
                self.ui.title_bar:addButton({
                    icon = "book",
                    title = "Truyện Việt v" .. Version,
                    callback = function()
                        Browser:showRoot()
                    end,
                })
            end
        end
    end)

    Dispatcher:registerAction("start_truyenviet", {
        category = "none",
        event = "StartTruyenViet",
        title = "Truyện Việt v" .. Version,
        general = true,
    })
end

function TruyenViet:addToMainMenu(menu_items)
    local function openTruyenViet()
        Browser:showRoot()
    end
    local function openContinue()
        local Storage = require("truyenviet/storage")
        local SourceRegistry = require("truyenviet/source_registry")
        local history = Storage:getHistory()
        if #history > 0 then
            local latest = history[1]
            local src = SourceRegistry:get(latest.story.source_id)
            if src then
                Browser:loadStoryPage(latest.story, src, 1, function()
                    Browser:showRoot()
                end)
            else
                Browser:showHistory(function() Browser:showRoot() end)
            end
        else
            Browser:showRoot()
        end
    end

    local title_text = "🔥 Truyện Việt v" .. Version

    if self.ui and self.ui.name == "ReaderUI" then
        menu_items.truyenviet_reader_tools = {
            text = title_text,
            sorting_hint = "tools",
            callback = openTruyenViet,
        }
    else
        menu_items.truyenviet_search = {
            text = title_text,
            sorting_hint = "search",
            callback = openTruyenViet,
        }
        menu_items.truyenviet_tools = {
            text = title_text,
            sorting_hint = "tools",
            callback = openTruyenViet,
        }
        menu_items.truyenviet_main = {
            text = title_text,
            sorting_hint = "main",
            callback = openTruyenViet,
        }
        menu_items.truyenviet_continue_search = {
            text = "📖 Truyện Việt: Tiếp tục đọc",
            sorting_hint = "search",
            callback = openContinue,
        }
        menu_items.truyenviet_continue_tools = {
            text = "📖 Truyện Việt: Tiếp tục đọc",
            sorting_hint = "tools",
            callback = openContinue,
        }
    end
end

function TruyenViet:onStartTruyenViet()
    Browser:showRoot()
end

return TruyenViet
