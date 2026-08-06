local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")

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
    local parsed = Util.parseJson(res)
    if type(parsed) ~= "table" then
        return nil, "Lỗi giải mã JSON từ Storya API"
    end
    return parsed
end

function Source:search(query)
    -- Storya search api endpoint
    local encoded = Util.urlEncode(query):gsub("%%20", "+")
    local parsed, err = apiGet("/stories/search?q=" .. encoded)
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
    local story_slug = story.url:match("/truyen/([^/?]+)") or story.url
    -- Tối ưu: Lấy list chapters qua API với limit lớn (100)
    local parsed, err = apiGet("/chapters/story/" .. story_slug .. "?page=" .. page .. "&limit=100&minimal=true")
    if not parsed or not parsed.data then return nil, err end

    local chapters = {}
    for _, item in ipairs(parsed.data) do
        local chap_order = item.order or 1
        local chap_slug = item.slug or ("chuong-" .. chap_order)
        table.insert(chapters, {
            title = item.title or ("Chương " .. chap_order),
            -- Tối ưu: Lưu trữ trực tiếp chap_slug vào URL để getChapter gọi API dễ dàng
            url = self.base_url .. "/truyen/" .. story_slug .. "/" .. chap_slug,
            order = chap_order,
            slug = story_slug,
            chap_slug = chap_slug,
            source_id = self.id,
            story_url = story.url,
            kind = "text",
        })
    end

    local meta = parsed.meta or {}
    if page == 1 then
        story.details = self:getStoryDetails(story)
    end

    return {
        story = story,
        chapters = chapters,
        page = page,
        total_pages = meta.totalPages or 1,
    }
end

function Source:getChapter(chapter)
    local story_slug = chapter.slug
    local chap_slug = chapter.chap_slug
    
    if not story_slug or not chap_slug then
        story_slug, chap_slug = chapter.url:match("/truyen/([^/]+)/([^/?]+)")
    end

    if not story_slug or not chap_slug then
        return nil, "Không nhận diện được slug chương Storya"
    end

    -- Tối ưu: Gọi trực tiếp API nội dung chương theo cấu trúc /chapters/{story}/{chap}
    local parsed, err = apiGet("/chapters/" .. story_slug .. "/" .. chap_slug)
    if not parsed or not parsed.data then
        return nil, err or "Không tìm thấy nội dung chương"
    end

    local item = parsed.data
    local raw_content = item.rewrittenContent or item.content or item.rawContent or ""
    local content = ""

    if raw_content ~= "" then
        if raw_content:find("<p>") then
            content = raw_content
        else
            -- Tối ưu: Thay thế xuống dòng thành thẻ HTML <br>
            local formatted = raw_content:gsub("\r\n", "\n"):gsub("\n\n", "<br><br>"):gsub("\n", "<br>")
            content = "<div>" .. formatted .. "</div>"
        end
    end

    if content == "" then
        return nil, "Nội dung chương rỗng"
    end

    return {
        title = item.title or chapter.title,
        content = content,
        url = chapter.url,
        kind = "text",
    }
end

function Source:getHot(page)
    page = page or 1
    local parsed, err = apiGet("/stories/hot?page=" .. page .. "&limit=20")
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
        title = "Truyện Hot",
    }
end

function Source:getLatest(page)
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
        title = "Truyện Mới Nhất",
    }
end

return Source
