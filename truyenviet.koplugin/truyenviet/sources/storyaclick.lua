local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local ko_util = require("util")
local dkjson = require("json")

-- Storya.click — Trang đọc truyện Next.js Client-rendered với REST API JSON
local Source = {
    id = "storyaclick",
    name = "Storya",
    kind = "text",
    base_url = "https://storya.click",
}

local function apiGet(endpoint)
    local url = "https://storya.click/api/v1" .. endpoint
    local res, err = Http:get(url, {
        ["Accept"] = "application/json",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not res then return nil, err end
    local ok, parsed = pcall(dkjson.decode, res)
    if not ok or type(parsed) ~= "table" then
        return nil, "Lỗi giải mã JSON từ Storya API"
    end
    return parsed
end

function Source:search(query)
    local encoded = ko_util.urlEncode(query):gsub("%%20", "+")
    local parsed, err = apiGet("/stories?page=1&limit=30&search=" .. encoded)
    if not parsed or not parsed.data then return nil, err end

    local stories = {}
    for _, item in ipairs(parsed.data) do
        local cover = item.coverUrl
        if cover and cover:sub(1, 1) == "/" then
            cover = self.base_url .. cover
        end
        table.insert(stories, {
            source_id = self.id,
            title = item.title or "Chưa có tiêu đề",
            url = self.base_url .. "/truyen/" .. item.slug,
            cover_url = cover,
            kind = "text",
        })
    end
    return stories
end

function Source:getCompleted(page)
    page = page or 1
    local parsed, err = apiGet("/stories?page=" .. page .. "&limit=20")
    if not parsed or not parsed.data then return nil, err end

    local stories = {}
    for _, item in ipairs(parsed.data) do
        local cover = item.coverUrl
        if cover and cover:sub(1, 1) == "/" then
            cover = self.base_url .. cover
        end
        table.insert(stories, {
            source_id = self.id,
            title = item.title or "Chưa có tiêu đề",
            url = self.base_url .. "/truyen/" .. item.slug,
            cover_url = cover,
            kind = "text",
        })
    end

    local meta = parsed.meta or {}
    return {
        stories = stories,
        genres = self:getGenresList() or {},
        page = page,
        total_pages = meta.totalPages or 1,
        title = "Truyện mới nhất",
    }
end

function Source:getGenresList()
    local parsed, err = apiGet("/genres")
    if not parsed or not parsed.data then return nil, err end

    local genres = {}
    for _, item in ipairs(parsed.data) do
        if item.name and item.slug then
            table.insert(genres, {
                name = item.name,
                url = self.base_url .. "/the-loai/" .. item.slug,
                slug = item.slug,
                id = item.id,
            })
        end
    end
    return genres
end

function Source:getGenre(genre, page)
    page = page or 1
    local slug = type(genre) == "table" and (genre.slug or (genre.url and genre.url:match("/the%-loai/([^/?]+)"))) or "linh-di"
    local parsed, err = apiGet("/genres/slug/" .. slug)
    if not parsed or not parsed.data then
        return self:getCompleted(page)
    end

    local raw_stories = parsed.data.stories or {}
    local stories = {}
    for _, item in ipairs(raw_stories) do
        local cover = item.coverUrl
        if cover and cover:sub(1, 1) == "/" then
            cover = self.base_url .. cover
        end
        table.insert(stories, {
            source_id = self.id,
            title = item.title or "Chưa có tiêu đề",
            url = self.base_url .. "/truyen/" .. item.slug,
            cover_url = cover,
            kind = "text",
        })
    end

    return {
        stories = stories,
        genres = self:getGenresList() or {},
        page = page,
        total_pages = 1,
        title = type(genre) == "table" and genre.name or ("Thể loại " .. slug),
    }
end

function Source:getStoryDetails(story)
    local slug = story.url:match("/truyen/([^/?]+)") or story.url
    local parsed, err = apiGet("/stories/" .. slug)
    if not parsed or not parsed.data then return nil, err end

    local d = parsed.data
    local genres = {}
    if type(d.genres) == "table" then
        for _, g in ipairs(d.genres) do
            if g.name then table.insert(genres, g.name) end
        end
    end

    local author = d.author and d.author.name or "Đang cập nhật"
    local status = d.status == "COMPLETED" and "Hoàn thành" or "Đang cập nhật"

    return {
        description = d.description or d.rewrittenDescription or "",
        author = author,
        status = status,
        genres = genres,
    }
end

function Source:getStoryPage(story, page)
    page = page or 1
    local slug = story.url:match("/truyen/([^/?]+)") or story.url
    local parsed, err = apiGet("/chapters/story/" .. slug .. "?page=" .. page .. "&limit=50&minimal=true")
    if not parsed or not parsed.data then return nil, err end

    local chapters = {}
    for _, item in ipairs(parsed.data) do
        local chap_order = item.order or 1
        table.insert(chapters, {
            title = item.title or ("Chương " .. chap_order),
            url = self.base_url .. "/truyen/" .. slug .. "?chap=" .. chap_order,
            order = chap_order,
            slug = slug,
            source_id = self.id,
            story_url = story.url,
            kind = "text",
        })
    end

    local meta = parsed.meta or {}
    story.details = self:getStoryDetails(story)

    return {
        story = story,
        chapters = chapters,
        page = page,
        total_pages = meta.totalPages or 1,
    }
end

function Source:getChapter(chapter)
    local slug = chapter.slug or chapter.url:match("/truyen/([^/?]+)")
    local num = chapter.order or tonumber(chapter.url:match("chap=(%d+)")) or 1

    local parsed, err = apiGet("/chapters/story/" .. slug .. "?page=" .. num .. "&limit=1&minimal=false")
    if not parsed or not parsed.data or #parsed.data == 0 then
        return nil, err or "Không tìm thấy nội dung chương"
    end

    local item = parsed.data[1]
    local raw_content = item.content or item.rawContent or item.rewrittenContent or ""
    local content = ""

    if raw_content ~= "" then
        if raw_content:find("<p>") then
            content = raw_content
        else
            local paragraphs = {}
            for line in raw_content:gmatch("[^\r\n]+") do
                line = Util.trim(line)
                if #line > 0 then
                    table.insert(paragraphs, "<p>" .. Util.escapeHtml(line) .. "</p>")
                end
            end
            content = table.concat(paragraphs, "\n")
        end
    end

    if content == "" then
        return nil, "Nội dung chương rỗng"
    end

    local meta = parsed.meta or {}
    local total_chaps = meta.total or 1000

    return {
        title = item.title or chapter.title,
        content = content,
        previous_url = num > 1 and (self.base_url .. "/truyen/" .. slug .. "?chap=" .. (num - 1)) or nil,
        next_url = num < total_chaps and (self.base_url .. "/truyen/" .. slug .. "?chap=" .. (num + 1)) or nil,
        url = chapter.url,
        kind = "text",
    }
end

return Source
