local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local ko_util = require("util")
local Util = require("truyenviet/helpers")

local Storage = {
    settings = nil,
    root_dir = nil,
    cache_dir = nil,
    disabled_sources = nil,
}

local function copyTable(value)
    local result = {}
    for key, item in pairs(type(value) == "table" and value or {}) do
        result[key] = item
    end
    return result
end

local function persistSetting(self, key, value)
    local previous = self.settings:readSetting(key)
    local ok, err = pcall(function()
        self.settings:saveSetting(key, value)
        self.settings:flush()
    end)
    if not ok then
        pcall(self.settings.saveSetting, self.settings, key, previous)
        return nil, tostring(err)
    end
    return true
end

function Storage:initialize()
    if self.settings then
        return
    end

    self.root_dir = ffiutil.joinPath(DataStorage:getFullDataDir(), "truyenviet")
    ko_util.makePath(self.root_dir)
    self.cache_dir = ffiutil.joinPath(self.root_dir, "cache")
    ko_util.makePath(self.cache_dir)
    self.settings = LuaSettings:open(
        ffiutil.joinPath(DataStorage:getSettingsDir(), "truyenviet.lua")
    )
    self.disabled_sources = {}
    local disabled_sources = self.settings:readSetting("disabled_sources", {})
    if type(disabled_sources) ~= "table" then
        disabled_sources = {}
    end
    for source_id, disabled in pairs(disabled_sources) do
        if disabled == true then
            self.disabled_sources[source_id] = true
        end
    end
end

function Storage:getRootDir()
    self:initialize()
    return self.root_dir
end

function Storage:getCoverCacheDir()
    self:initialize()
    local path = ffiutil.joinPath(self.cache_dir, "covers")
    ko_util.makePath(path)
    return path
end

function Storage:clearCoverCacheDir()
    local dir = self:getCoverCacheDir()
    local ok = pcall(function()
        for file in lfs.dir(dir) do
            if file ~= "." and file ~= ".." then
                local path = ffiutil.joinPath(dir, file)
                if lfs.attributes(path, "mode") == "file" then
                    os.remove(path)
                end
            end
        end
    end)
    return ok
end

function Storage:getCustomBaseUrl(source_id)
    self:initialize()
    local url = self.settings:readSetting("custom_url_" .. source_id)
    return type(url) == "string" and url ~= "" and url or nil
end

function Storage:setCustomBaseUrl(source_id, url)
    self:initialize()
    if url and url ~= "" then
        url = url:match("^%s*(.-)%s*$"):gsub("/+$", "")
        if url == "" then
            url = nil
        end
    end
    return persistSetting(self, "custom_url_" .. source_id, url)
end

function Storage:getSourceOrder()
    self:initialize()
    local order = self.settings:readSetting("source_order")
    return type(order) == "table" and order or {}
end

function Storage:setSourceOrder(order)
    self:initialize()
    return persistSetting(self, "source_order", order)
end

function Storage:setFastMode(enabled)
    self:initialize()
    return persistSetting(self, "fast_mode", enabled == true)
end

function Storage:isSourceEnabled(source_id)
    self:initialize()
    return self.disabled_sources[source_id] ~= true
end

function Storage:setSourceEnabled(source_id, enabled)
    self:initialize()
    local was_disabled = self.disabled_sources[source_id] == true
    if enabled then
        self.disabled_sources[source_id] = nil
    else
        self.disabled_sources[source_id] = true
    end

    local saved = {}
    for id, disabled in pairs(self.disabled_sources) do
        if disabled == true then
            saved[id] = true
        end
    end

    local ok, err = pcall(function()
        self.settings:saveSetting("disabled_sources", saved)
        self.settings:flush()
    end)
    if not ok then
        self.disabled_sources[source_id] = was_disabled and true or nil
        return nil, tostring(err)
    end
    return true
end

function Storage:getStoryDir(source, story)
    self:initialize()
    local source_dir = ffiutil.joinPath(self.root_dir, source.id)
    local story_dir = ffiutil.joinPath(source_dir, Util.urlLeaf(story.url, "story"))
    ko_util.makePath(story_dir)
    return story_dir
end

function Storage:getChapterPath(source, story, chapter)
    local extension = source.kind == "comic" and ".cbz" or ".html"
    local filename = Util.urlLeaf(chapter.url, Util.safeName(chapter.title, "chapter"))
    return ffiutil.joinPath(self:getStoryDir(source, story), filename .. extension)
end

function Storage:isDownloaded(source, story, chapter)
    return lfs.attributes(self:getChapterPath(source, story, chapter), "mode") == "file"
end

function Storage:removeDownload(source, story, chapter)
    local path = self:getChapterPath(source, story, chapter)
    if lfs.attributes(path, "mode") == "file" then
        return os.remove(path)
    end
    return true
end

function Storage:removeAllDownloads()
    local path = self:getRootDir()
    if lfs.attributes(path, "mode") ~= "directory" then return true end

    local function rmdir_recursive(dir_path)
        for file in lfs.dir(dir_path) do
            if file ~= "." and file ~= ".." then
                local full_path = dir_path .. "/" .. file
                if lfs.attributes(full_path, "mode") == "directory" then
                    rmdir_recursive(full_path)
                else
                    os.remove(full_path)
                end
            end
        end
        lfs.rmdir(dir_path)
    end

    local ok, err = pcall(rmdir_recursive, path)
    -- Recreate the root directory after deletion
    lfs.mkdir(path)
    return ok, err
end

function Storage:getFavorites()
    self:initialize()
    local favorites = self.settings:readSetting("favorites", {})
    return type(favorites) == "table" and favorites or {}
end

function Storage:isFavorite(story)
    if not story or not story.source_id or not story.url then return false end
    return self:getFavorites()[story.source_id .. "|" .. story.url] ~= nil
end

local function favoriteRecord(story)
    return {
        source_id = story.source_id,
        title = story.title,
        url = story.url,
        cover_url = story.cover_url,
        kind = story.kind,
        details = story.details,
    }
end

function Storage:addFavorite(story)
    local favorites = copyTable(self:getFavorites())
    favorites[story.source_id .. "|" .. story.url] = favoriteRecord(story)
    return persistSetting(self, "favorites", favorites)
end

function Storage:updateFavorite(story)
    if self:isFavorite(story) then
        return self:addFavorite(story)
    end
    return true
end

function Storage:removeFavorite(story)
    local favorites = copyTable(self:getFavorites())
    favorites[story.source_id .. "|" .. story.url] = nil
    return persistSetting(self, "favorites", favorites)
end

-- Xóa tất cả file đã tải của một truyện (dùng cho xóa hết)
local function deleteStoryDownloads(self, story_record)
    local source_dir = ffiutil.joinPath(self.root_dir, story_record.source_id)
    local story_dir = ffiutil.joinPath(source_dir, Util.urlLeaf(story_record.url, "story"))
    if lfs.attributes(story_dir, "mode") ~= "directory" then return end
    local function rmdir(dir)
        for file in lfs.dir(dir) do
            if file ~= "." and file ~= ".." then
                local fp = dir .. "/" .. file
                if lfs.attributes(fp, "mode") == "directory" then
                    rmdir(fp)
                else
                    os.remove(fp)
                end
            end
        end
        lfs.rmdir(dir)
    end
    pcall(rmdir, story_dir)
end

function Storage:clearAllFavorites(with_downloads)
    self:initialize()
    if with_downloads then
        for _, story in pairs(self:getFavorites()) do
            if type(story) == "table" then
                pcall(deleteStoryDownloads, self, story)
            end
        end
    end
    return persistSetting(self, "favorites", {})
end

function Storage:listFavorites()
    local result = {}
    for _, story in pairs(self:getFavorites()) do
        if type(story) == "table"
                and type(story.title) == "string"
                and type(story.url) == "string"
                and type(story.source_id) == "string" then
            table.insert(result, story)
        end
    end
    table.sort(result, function(left, right)
        return left.title:lower() < right.title:lower()
    end)
    return result
end

function Storage:getHistory()
    self:initialize()
    local history = self.settings:readSetting("history", {})
    if type(history) ~= "table" then
        return {}
    end

    local valid_history = {}
    for _, item in ipairs(history) do
        if type(item) == "table"
                and type(item.story) == "table"
                and type(item.story.source_id) == "string"
                and type(item.story.title) == "string"
                and type(item.story.url) == "string"
                and type(item.chapter) == "table"
                and type(item.chapter.title) == "string"
                and type(item.chapter.url) == "string" then
            table.insert(valid_history, item)
        end
    end
    return valid_history
end

function Storage:saveHistory(story, chapter)
    local history = copyTable(self:getHistory())
    local existing_idx
    for i, item in ipairs(history) do
        if item.story.source_id == story.source_id and item.story.url == story.url then
            existing_idx = i
            break
        end
    end
    if existing_idx then
        table.remove(history, existing_idx)
    end
    
    local clean_story = favoriteRecord(story)
    table.insert(history, 1, {
        story = clean_story,
        chapter = {
            title = chapter.title,
            url = chapter.url,
        },
        time = os.time(),
    })
    
    while #history > 100 do
        table.remove(history)
    end
    
    return persistSetting(self, "history", history)
end

function Storage:removeHistory(story)
    local history = copyTable(self:getHistory())
    local existing_idx
    for i, item in ipairs(history) do
        if item.story.source_id == story.source_id and item.story.url == story.url then
            existing_idx = i
            break
        end
    end
    if existing_idx then
        table.remove(history, existing_idx)
        return persistSetting(self, "history", history)
    end
    return true
end

function Storage:clearAllHistory(with_downloads)
    self:initialize()
    if with_downloads then
        for _, item in ipairs(self:getHistory()) do
            if type(item) == "table" and type(item.story) == "table" then
                pcall(deleteStoryDownloads, self, item.story)
            end
        end
    end
    return persistSetting(self, "history", {})
end

-- Ebook storage methods for TVE-4U and Dilib sources

function Storage:getEbookDir(source, book)
    self:initialize()
    local source_dir = ffiutil.joinPath(self.root_dir, source.id)
    local book_slug = Util.urlLeaf(book.url, Util.safeName(book.title, "book"))
    local book_dir = ffiutil.joinPath(source_dir, book_slug)
    ko_util.makePath(book_dir)
    return book_dir
end

function Storage:getEbookPath(source, book, filename)
    return ffiutil.joinPath(self:getEbookDir(source, book), Util.safeName(filename, "file"))
end

function Storage:isEbookDownloaded(source, book, filename)
    local path = self:getEbookPath(source, book, filename)
    return lfs.attributes(path, "mode") == "file", path
end

function Storage:isPrefetchEnabled()
    self:initialize()
    return self.settings:readSetting("prefetch_enabled", true) == true
end

function Storage:setPrefetchEnabled(enabled)
    self:initialize()
    return persistSetting(self, "prefetch_enabled", enabled == true)
end

function Storage:getPrefetchCount()
    self:initialize()
    return tonumber(self.settings:readSetting("prefetch_count", 3)) or 3
end

function Storage:setPrefetchCount(count)
    self:initialize()
    return persistSetting(self, "prefetch_count", tonumber(count) or 3)
end

function Storage:isAutoPurgeEnabled()
    self:initialize()
    return self.settings:readSetting("auto_purge_enabled", true) == true
end

function Storage:setAutoPurgeEnabled(enabled)
    self:initialize()
    return persistSetting(self, "auto_purge_enabled", enabled == true)
end

function Storage:getPurgeDistance()
    self:initialize()
    return tonumber(self.settings:readSetting("purge_distance", 5)) or 5
end

function Storage:setPurgeDistance(distance)
    self:initialize()
    return persistSetting(self, "purge_distance", tonumber(distance) or 5)
end

-- Quản lý File Đã Tải (Downloaded Files Management)

function Storage:listDownloadedStories()
    self:initialize()
    local result = {}
    local path = self.root_dir
    if lfs.attributes(path, "mode") ~= "directory" then return result end

    for source_id in lfs.dir(path) do
        if source_id ~= "." and source_id ~= ".." and source_id ~= "cache" and source_id ~= "custom_sources" then
            local source_dir = ffiutil.joinPath(path, source_id)
            if lfs.attributes(source_dir, "mode") == "directory" then
                for story_slug in lfs.dir(source_dir) do
                    if story_slug ~= "." and story_slug ~= ".." then
                        local story_dir = ffiutil.joinPath(source_dir, story_slug)
                        if lfs.attributes(story_dir, "mode") == "directory" then
                            local chapter_count = 0
                            local total_bytes = 0
                            for file in lfs.dir(story_dir) do
                                if file ~= "." and file ~= ".." and not file:find("%.part$") then
                                    local fp = ffiutil.joinPath(story_dir, file)
                                    local attr = lfs.attributes(fp)
                                    if attr and attr.mode == "file" then
                                        chapter_count = chapter_count + 1
                                        total_bytes = total_bytes + (attr.size or 0)
                                    end
                                end
                            end
                            if chapter_count > 0 then
                                table.insert(result, {
                                    source_id = source_id,
                                    story_slug = story_slug,
                                    dir_path = story_dir,
                                    chapter_count = chapter_count,
                                    total_bytes = total_bytes,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

function Storage:listDownloadedChapters(source, story)
    local dir = self:getStoryDir(source, story)
    local chapters = {}
    if lfs.attributes(dir, "mode") == "directory" then
        for file in lfs.dir(dir) do
            if file ~= "." and file ~= ".." and not file:find("%.part$") then
                local lower_f = file:lower()
                if (lower_f:find("%.html$") or lower_f:find("%.htm$") or lower_f:find("%.txt$")) and not lower_f:find("^cover%.") then
                    local fp = ffiutil.joinPath(dir, file)
                    local attr = lfs.attributes(fp)
                    if attr and attr.mode == "file" then
                        table.insert(chapters, {
                            filename = file,
                            path = fp,
                            size = attr.size,
                        })
                    end
                end
            end
        end
    end
    table.sort(chapters, function(a, b) return a.filename < b.filename end)
    return chapters
end

function Storage:deleteChapters(source, story, chapter_filenames)
    local dir = self:getStoryDir(source, story)
    local count = 0
    for _, fname in ipairs(chapter_filenames or {}) do
        local fp = ffiutil.joinPath(dir, fname)
        if lfs.attributes(fp, "mode") == "file" then
            if os.remove(fp) then
                count = count + 1
            end
        end
    end
    return count
end

function Storage:mergeChapters(source, story, options)
    options = options or {}
    local format = (options.format == "html") and "html" or "epub"
    local include_cover = options.include_cover ~= false
    local include_toc = options.include_toc ~= false
    local delete_source_files = options.delete_source_files == true

    local ok, res, err_msg, chapters = pcall(function()
        local dir = self:getStoryDir(source, story)
        local chapters = self:listDownloadedChapters(source, story)
        if #chapters == 0 then
            return nil, "Không có chương nào để gộp"
        end

        local raw_name = options.output_filename
        if not raw_name or raw_name == "" then
            raw_name = Util.safeName(story.title or story.url, "story") .. "_gop"
        else
            raw_name = Util.safeName(raw_name, "story")
        end

        local output_filename = raw_name .. "." .. format
        local output_path = ffiutil.joinPath(self:getRootDir(), output_filename)

        local out_file, err = io.open(output_path, "w")
        if not out_file then
            return nil, "Không thể tạo file gộp: " .. tostring(err)
        end

        -- 1. Tìm ảnh bìa trong cache hoặc thư mục truyện (nếu include_cover = true)
        local cover_b64 = nil
        local cover_mime = "image/jpeg"
        if include_cover then
            local cover_path = nil
            pcall(function()
                local CoverCache = require("truyenviet/cover_cache")
                cover_path = CoverCache:get(story)
            end)

            if not cover_path and lfs.attributes(dir, "mode") == "directory" then
                for _, ext in ipairs({"jpg", "png", "webp", "jpeg"}) do
                    local p = ffiutil.joinPath(dir, "cover." .. ext)
                    if lfs.attributes(p, "mode") == "file" then
                        cover_path = p
                        break
                    end
                end
            end

            if cover_path then
                local img_f = io.open(cover_path, "rb")
                if img_f then
                    local data = img_f:read("*a")
                    img_f:close()
                    if data and #data > 0 then
                        local ok_mime, mime = pcall(require, "mime")
                        if ok_mime and mime and type(mime.b64) == "function" then
                            local ok_b64, b64_res = pcall(mime.b64, data)
                            if ok_b64 and b64_res then
                                cover_b64 = b64_res
                                if cover_path:find("%.png$") then
                                    cover_mime = "image/png"
                                elseif cover_path:find("%.webp$") then
                                    cover_mime = "image/webp"
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 2. Bóc tách danh sách tiêu đề & nội dung các chương
        local chapter_data = {}
        for i, chap in ipairs(chapters) do
            local f = io.open(chap.path, "r")
            if f then
                local content = f:read("*a")
                f:close()
                if content then
                    local title = content:match("<title>(.-)</title>")
                        or content:match("<h[12][^>]*>(.-)</h[12]>")
                        or chap.filename:gsub("%.html$", ""):gsub("^%d+_%d+_", "")
                    title = Util.decodeHtml(Util.stripTags(title or ""))
                    if title == "" then
                        title = "Chương " .. i
                    end

                    local body = content:match("<body[^>]*>([%s%S]-)</body>") or content
                    table.insert(chapter_data, {
                        index = i,
                        title = title,
                        body = body,
                        path = chap.path,
                    })
                end
            end
        end

        -- 3. Viết Header HTML & CSS
        out_file:write("<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n")
        out_file:write("<title>" .. Util.encodeHtml(story.title or "Truyện") .. "</title>\n")
        out_file:write("<style>\n")
        out_file:write("  body { font-family: sans-serif; margin: 0; padding: 20px; line-height: 1.6; }\n")
        out_file:write("  .cover-box { text-align: center; page-break-after: always; padding: 20px 0; }\n")
        out_file:write("  .cover-box img { max-width: 100%; max-height: 85vh; height: auto; border-radius: 6px; box-shadow: 0 4px 12px rgba(0,0,0,0.2); }\n")
        out_file:write("  .story-main-title { text-align: center; margin-top: 15px; font-size: 2em; }\n")
        out_file:write("  .toc-box { page-break-after: always; padding: 10px 0; }\n")
        out_file:write("  .toc-title { text-align: center; border-bottom: 2px solid #333; padding-bottom: 8px; margin-bottom: 20px; font-size: 1.6em; }\n")
        out_file:write("  .toc-list { list-style-type: none; padding-left: 0; line-height: 2.2; }\n")
        out_file:write("  .toc-item { border-bottom: 1px dashed #ddd; padding: 6px 0; }\n")
        out_file:write("  .toc-item a { text-decoration: none; color: #1a0dab; font-size: 1.1em; display: block; }\n")
        out_file:write("  .chapter-block { page-break-before: always; padding-top: 15px; }\n")
        out_file:write("</style>\n</head>\n<body>\n")

        -- TRANG BÌA (COVER PAGE)
        if include_cover then
            if cover_b64 then
                out_file:write("<div class=\"cover-box\">\n")
                out_file:write("  <img src=\"data:" .. cover_mime .. ";base64," .. cover_b64 .. "\" alt=\"Cover\" />\n")
                out_file:write("  <h1 class=\"story-main-title\">" .. Util.encodeHtml(story.title or "Truyện") .. "</h1>\n")
                out_file:write("</div>\n")
            else
                out_file:write("<div class=\"cover-box\">\n")
                out_file:write("  <h1 class=\"story-main-title\">" .. Util.encodeHtml(story.title or "Truyện") .. "</h1>\n")
                out_file:write("</div>\n")
            end
        end

        -- MỤC LỤC TRUYỆN (TABLE OF CONTENTS)
        if include_toc then
            out_file:write("<div class=\"toc-box\">\n")
            out_file:write("  <h2 class=\"toc-title\">MỤC LỤC TRUYỆN</h2>\n")
            out_file:write("  <ul class=\"toc-list\">\n")
            for _, item in ipairs(chapter_data) do
                out_file:write("    <li class=\"toc-item\"><a href=\"#chap_" .. item.index .. "\">" .. Util.encodeHtml(item.title) .. "</a></li>\n")
            end
            out_file:write("  </ul>\n")
            out_file:write("</div>\n")
        end

        -- NỘI DUNG CÁC CHƯƠNG TRUYỆN
        for _, item in ipairs(chapter_data) do
            out_file:write("<div id=\"chap_" .. item.index .. "\" class=\"chapter-block\">\n")
            out_file:write(item.body .. "\n")
            out_file:write("</div>\n")
        end

        out_file:write("</body>\n</html>\n")
        out_file:close()

        -- 4. Xóa file gốc nếu được bật
        if delete_source_files then
            pcall(function()
                for f in lfs.dir(dir) do
                    if f ~= "." and f ~= ".." then
                        os.remove(dir .. "/" .. f)
                    end
                end
                lfs.rmdir(dir)
            end)
        end

        return output_path, nil, chapters
    end)

    if ok then
        return res, err_msg, chapters
    else
        return nil, tostring(res)
    end
end

function Storage:mergeChaptersToEpub(source, story, output_path)
    return self:mergeChapters(source, story, {
        format = "epub",
        include_cover = true,
        include_toc = true,
        output_filename = output_path,
        delete_source_files = false,
    })
end

return Storage



