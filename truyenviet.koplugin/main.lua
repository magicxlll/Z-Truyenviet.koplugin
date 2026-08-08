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
    end)

    self:onDispatcherRegisterActions()
end

function TruyenViet:onDispatcherRegisterActions()
    Dispatcher:registerAction("start_truyenviet", {
        category = "none",
        event = "StartTruyenViet",
        title = "🔥 Truyện Việt",
        general = true,
        reader = true,
        filemanager = true,
    })

    Dispatcher:registerAction("truyenviet_chapter_list", {
        category = "none",
        event = "TruyenVietBackToChapters",
        title = "📋 Truyện Việt: Danh sách chương",
        general = true,
        reader = true,
        filemanager = true,
    })

    Dispatcher:registerAction("truyenviet_continue", {
        category = "none",
        event = "TruyenVietContinue",
        title = "📖 Truyện Việt: Tiếp tục đọc",
        general = true,
        reader = true,
        filemanager = true,
    })

    Dispatcher:registerAction("truyenviet_history", {
        category = "none",
        event = "TruyenVietHistory",
        title = "📜 Truyện Việt: Lịch sử đọc",
        general = true,
        reader = true,
        filemanager = true,
    })

    Dispatcher:registerAction("truyenviet_downloaded", {
        category = "none",
        event = "TruyenVietDownloaded",
        title = "💾 Truyện Việt: Đã tải xuống",
        general = true,
        reader = true,
        filemanager = true,
    })

    Dispatcher:registerAction("truyenviet_next_chapter", {
        category = "none",
        event = "TruyenVietNextChapter",
        title = "➡️ Truyện Việt: Chương tiếp",
        general = true,
        reader = true,
        filemanager = true,
    })

    Dispatcher:registerAction("truyenviet_prev_chapter", {
        category = "none",
        event = "TruyenVietPrevChapter",
        title = "⬅️ Truyện Việt: Chương trước",
        general = true,
        reader = true,
        filemanager = true,
    })

    Dispatcher:registerAction("truyenviet_story_page", {
        category = "none",
        event = "TruyenVietStoryPage",
        title = "🏠 Truyện Việt: Nguồn truyện",
        general = true,
        reader = true,
        filemanager = true,
    })
end

function TruyenViet:addToMainMenu(menu_items)
    local title_text = "🔥 Truyện Việt v" .. Version

    local sub_items = {
        {
            text = "🔥 Mở Truyện Việt (Trang chủ)",
            callback = function()
                self:onStartTruyenViet()
            end,
        },
        {
            text = "📖 Tiếp tục đọc",
            callback = function()
                self:onTruyenVietContinue()
            end,
        },
        {
            text = "📋 Danh sách chương",
            callback = function()
                self:onTruyenVietBackToChapters()
            end,
        },
        {
            text = "➡️ Chương tiếp",
            callback = function()
                self:onTruyenVietNextChapter()
            end,
        },
        {
            text = "⬅️ Chương trước",
            callback = function()
                self:onTruyenVietPrevChapter()
            end,
        },
        {
            text = "🏠 Về nguồn truyện",
            callback = function()
                self:onTruyenVietStoryPage()
            end,
        },
        {
            text = "📜 Lịch sử đọc",
            callback = function()
                self:onTruyenVietHistory()
            end,
        },
        {
            text = "💾 Đã tải xuống",
            callback = function()
                self:onTruyenVietDownloaded()
            end,
        },
    }

    menu_items.truyenviet = {
        text = title_text,
        sorting_hint = "tools",
        sub_item_table = sub_items,
    }

    if self.ui and self.ui.name == "ReaderUI" then
        menu_items.truyenviet_reader_tools = {
            text = title_text,
            sorting_hint = "tools",
            sub_item_table = sub_items,
        }
    else
        menu_items.truyenviet_search = {
            text = title_text,
            sorting_hint = "search",
            sub_item_table = sub_items,
        }
        menu_items.truyenviet_tools = {
            text = title_text,
            sorting_hint = "tools",
            sub_item_table = sub_items,
        }
    end
end

function TruyenViet:onStartTruyenViet()
    Browser:showRoot()
end

function TruyenViet:onTruyenVietBackToChapters()
    local Reader = require("truyenviet/reader")
    local ReaderUI = require("apps/reader/readerui")
    if Reader.active and ReaderUI.instance then
        Reader:returnToPlugin()
    else
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
end

function TruyenViet:onTruyenVietContinue()
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

function TruyenViet:onTruyenVietHistory()
    Browser:showHistory(function() Browser:showRoot() end)
end

function TruyenViet:onTruyenVietDownloaded()
    Browser:showDownloadedManager(function() Browser:showRoot() end)
end






function TruyenViet:onTruyenVietNextChapter()
    local Reader = require("truyenviet/reader")
    if Reader.on_next_chapter_callback then
        Reader.on_next_chapter_callback(true)
    end
end

function TruyenViet:onTruyenVietPrevChapter()
    local Reader = require("truyenviet/reader")
    if Reader.on_prev_chapter_callback then
        Reader.on_prev_chapter_callback(true)
    end
end

function TruyenViet:onTruyenVietStoryPage()
    local Reader = require("truyenviet/reader")
    if Reader.active then
        Reader:returnToPlugin(function()
            Browser:showRoot()
        end)
    else
        Browser:showRoot()
    end
end
return TruyenViet
