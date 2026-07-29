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
    local FontHelper = require("truyenviet/font_helper")
    FontHelper:setupComicFont()

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

    -- Đăng ký vào tất cả các tab Menu (Main, Tools, Search, File, Document)
    menu_items.truyenviet_main = {
        text = title_text,
        sorting_hint = "main",
        callback = openTruyenViet,
    }
    menu_items.truyenviet_tools = {
        text = title_text,
        sorting_hint = "tools",
        callback = openTruyenViet,
    }
    menu_items.truyenviet_search = {
        text = title_text,
        sorting_hint = "search",
        callback = openTruyenViet,
    }
    menu_items.truyenviet_file = {
        text = title_text,
        sorting_hint = "file",
        callback = openTruyenViet,
    }
    menu_items.truyenviet_document = {
        text = title_text,
        sorting_hint = "document",
        callback = openTruyenViet,
    }

    menu_items.truyenviet_continue_main = {
        text = "📖 Truyện Việt: Tiếp tục đọc",
        sorting_hint = "main",
        callback = openContinue,
    }
    menu_items.truyenviet_continue_tools = {
        text = "📖 Truyện Việt: Tiếp tục đọc",
        sorting_hint = "tools",
        callback = openContinue,
    }
end

function TruyenViet:onStartTruyenViet()
    Browser:showRoot()
end

return TruyenViet
