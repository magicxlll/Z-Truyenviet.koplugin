local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local ko_util = require("util")

local Source = {
    id = "conduongbachu",
    name = "Con Đường Bá Chủ",
    kind = "text",
    base_url = "https://conduongbachu.com",
    reversed_chapters = false,
    _chapter_index = {},
}

local PAGE_SIZE = 50

local STORIES = {
    {
        id = "main",
        cat_id = 3,
        title = "Con Đường Bá Chủ (Chính Truyện)",
        url = "https://conduongbachu.com/",
        slug = "chapter-truyen",
        cover_url = "https://conduongbachu.com/wp-content/uploads/2024/12/20355-con-duong-ba-chu_cover_large.webp",
    },
    {
        id = "bat-hu-than-chien",
        cat_id = 12,
        title = "Ngoại Truyện: Bất Hủ Thần Chiến",
        url = "https://conduongbachu.com/ngoai-truyen/",
        slug = "ngoai-truyen",
        cover_url = "https://conduongbachu.com/wp-content/uploads/2025/04/conduongbachu-ngoai-truyen-268x400.jpg",
    },
    {
        id = "van-dao-than-chu",
        cat_id = 14,
        title = "Ngoại Truyện: Vạn Đạo Thần Chủ",
        url = "https://conduongbachu.com/ngoai-truyen-van-dao-than-chu/",
        slug = "ngoai-truyen-van-dao-than-chu",
        cover_url = "https://conduongbachu.com/wp-content/uploads/2024/12/20355-con-duong-ba-chu_cover_large.webp",
    },
    {
        id = "chua-te-chi-lo",
        cat_id = 15,
        title = "Ngoại Truyện: Chúa Tể Chi Lộ",
        url = "https://conduongbachu.com/ngoai-truyen-chua-te-chi-lo/",
        slug = "ngoai-truyen-chua-te-chi-lo",
        cover_url = "https://conduongbachu.com/wp-content/uploads/2024/12/20355-con-duong-ba-chu_cover_large.webp",
    },
}

local function stdHeaders(base_url)
    return {
        ["Referer"] = base_url .. "/",
        ["Accept"] = "text/html,application/xhtml+xml,application/json",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    }
end

local function absolute(base_url, href)
    return Util.absoluteUrl(base_url, href)
end

local function detectStoryConfig(story_or_url)
    local target_url = type(story_or_url) == "table" and story_or_url.url or tostring(story_or_url or "")
    target_url = target_url:gsub("%?.*$", ""):gsub("/$", "") .. "/"

    for _, config in ipairs(STORIES) do
        local config_url = config.url:gsub("/$", "") .. "/"
        if target_url == config_url or target_url:find(config.slug, 1, true) then
            return config
        end
    end
    return STORIES[1]
end

local function parseChapterNumber(title, url)
    return tonumber((title or ""):match("[Cc]hương%s*(%d+)"))
        or tonumber((title or ""):match("(%d+)"))
        or tonumber((url or ""):match("/chuong%-(%d+)"))
        or 0
end

local function uniqueChapters(chapters)
    local unique = {}
    local seen = {}
    for _, ch in ipairs(chapters or {}) do
        if ch.url and not seen[ch.url] then
            seen[ch.url] = true
            table.insert(unique, ch)
        end
    end
    table.sort(unique, function(a, b)
        if a.number ~= b.number then
            return a.number < b.number
        end
        return a.url < b.url
    end)
    return unique
end

local function parseWpPosts(raw, base_url, source_id, story_url)
    local json = require("json")
    local ok, posts = pcall(json.decode, raw)
    if not ok or type(posts) ~= "table" then
        return nil
    end

    local chapters = {}
    for _, post in ipairs(posts) do
        local raw_title = post.title and post.title.rendered or ""
        local title = Util.trim(Util.stripTags(raw_title))
        title = Util.decodeHtml(title)
        local link = post.link and absolute(base_url, post.link) or nil

        if link and title ~= "" then
            local number = parseChapterNumber(title, link)
            table.insert(chapters, {
                title = title,
                url = link,
                number = number,
                order = number,
                source_id = source_id,
                story_url = story_url,
                kind = "text",
            })
        end
    end
    return chapters
end

local function chapterIndex(self, story)
    local config = detectStoryConfig(story)
    local cache_key = config.id
    if self._chapter_index[cache_key] then
        return self._chapter_index[cache_key]
    end

    local story_url = config.url
    local api_url = self.base_url .. "/wp-json/wp/v2/posts?categories=" .. config.cat_id .. "&per_page=100&_fields=link,title"
    local raw_json = Http:get(api_url, stdHeaders(self.base_url))

    local chapters = {}
    if raw_json then
        local first_chapters = parseWpPosts(raw_json, self.base_url, self.id, story_url)
        if first_chapters then
            for _, ch in ipairs(first_chapters) do
                table.insert(chapters, ch)
            end
        end
    end

    chapters = uniqueChapters(chapters)
    self._chapter_index[cache_key] = chapters
    return chapters
end

function Source:parseSearch(html, query)
    local result = {}
    local query_lower = query and query:lower() or ""

    for _, config in ipairs(STORIES) do
        local matches = true
        if query_lower ~= "" then
            local title_lower = config.title:lower()
            matches = title_lower:find(query_lower, 1, true) or query_lower:find("con đường bá chủ", 1, true) or query_lower:find("bá chủ", 1, true) or query_lower:find("ngoại truyện", 1, true)
        end

        if matches then
            table.insert(result, {
                source_id = self.id,
                title = config.title,
                url = config.url,
                cover_url = config.cover_url,
                kind = self.kind,
            })
        end
    end
    return result
end

function Source:search(query)
    local encoded = ko_util.urlEncode(query or "")
    local html = Http:get(self.base_url .. "/?s=" .. encoded, stdHeaders(self.base_url))
    return self:parseSearch(html or "", query)
end

function Source:getCompleted(page)
    page = page or 1
    local stories = {}
    for _, config in ipairs(STORIES) do
        table.insert(stories, {
            source_id = self.id,
            title = config.title,
            url = config.url,
            cover_url = config.cover_url,
            kind = self.kind,
        })
    end

    return {
        stories = stories,
        genres = {
            { name = "Chính Truyện", url = "https://conduongbachu.com/chapter-truyen/" },
            { name = "Ngoại Truyện Bất Hủ Thần Chiến", url = "https://conduongbachu.com/ngoai-truyen/" },
            { name = "Ngoại Truyện Vạn Đạo Thần Chủ", url = "https://conduongbachu.com/ngoai-truyen-van-dao-than-chu/" },
            { name = "Ngoại Truyện Chúa Tể Chi Lộ", url = "https://conduongbachu.com/ngoai-truyen-chua-te-chi-lo/" },
        },
        page = page,
        total_pages = 1,
        title = "Con Đường Bá Chủ & Ngoại Truyện",
    }
end

function Source:getUpdating(page)
    return self:getCompleted(page)
end

function Source:getHot(page)
    return self:getCompleted(page)
end

function Source:getGenre(genre, page)
    return self:getCompleted(page)
end

function Source:getStoryDetails(story)
    local config = detectStoryConfig(story)
    local html, err = Http:get(config.url, stdHeaders(self.base_url))

    local description = html and html:match('<meta[^>]+name=["\']description["\'][^>]+content=["\']([^"\']+)') or ""
    local author = "Akay Hau"

    return {
        description = description ~= "" and Util.decodeHtml(description) or ("Bộ truyện: " .. config.title),
        author = author,
        status = "Hoàn thành / Đang cập nhật",
        genres = { "Huyền Huyễn", "Tiên Hiệp", "Bá Chủ", "Ngoại Truyện" },
    }
end

function Source:getStoryPage(story, page)
    page = math.max(1, tonumber(page) or 1)
    local chapters, err = chapterIndex(self, story)
    if not chapters then
        return nil, err
    end

    local total_pages = math.max(1, math.ceil(#chapters / PAGE_SIZE))
    if page > total_pages then
        page = total_pages
    end

    local first = (page - 1) * PAGE_SIZE + 1
    local page_chapters = {}
    for index = first, math.min(#chapters, first + PAGE_SIZE - 1) do
        local chapter = chapters[index]
        local copy = {}
        for key, value in pairs(chapter) do
            copy[key] = value
        end
        copy.story_url = story.url
        table.insert(page_chapters, copy)
    end

    story.details = story.details or self:getStoryDetails(story)
    return {
        story = story,
        chapters = page_chapters,
        page = page,
        total_pages = total_pages,
    }
end

function Source:getAllChapters(story)
    local chapters, err = chapterIndex(self, story)
    if not chapters then
        return nil, err
    end

    local result = {}
    for _, chapter in ipairs(chapters) do
        local copy = {}
        for key, value in pairs(chapter) do
            copy[key] = value
        end
        copy.story_url = story.url
        table.insert(result, copy)
    end
    return result
end

local function isNoiseParagraph(attrs, text)
    if attrs:find("post-tts", 1, true) then
        return true
    end
    return text:find("Nếu muốn tìm chương khác", 1, true) ~= nil
end

function Source:parseChapter(html, chapter)
    if not html then
        return nil, "Nội dung chương rỗng"
    end

    local title_html = html:match('<h1[^>]-class=["\'][^"\']*entry%-title[^"\']*["\'][^>]*>([%s%S]-)</h1>')
        or html:match("<h1[^>]*>([%s%S]-)</h1>")
    local title = title_html and Util.stripTags(title_html) or chapter.title

    local entry_start = html:find('<div[^>]-class=["\'][^"\']*entry%-content', 1)
    local nav_start = entry_start and html:find('<nav[^>]-id=["\']nav%-below["\']', entry_start)
    local region = entry_start and html:sub(entry_start, (nav_start or #html + 1) - 1) or html

    local paragraphs = {}
    for attrs, raw_body in region:gmatch("<p([^>]*)>([%s%S]-)</p>") do
        local text = Util.trim(Util.stripTags(raw_body))
        if text ~= "" and not isNoiseParagraph(attrs, text) then
            table.insert(paragraphs, "<p>" .. raw_body .. "</p>")
        end
    end

    if #paragraphs == 0 then
        return nil, "Không tìm thấy nội dung chương"
    end

    local previous_url = html:match('<a[^>]+rel=["\']prev["\'][^>]+href=["\']([^"\']+)')
        or html:match('<a[^>]+class=["\'][^"\']*prev%-btn[^"\']*["\'][^>]+href=["\']([^"\']+)')
    local next_url = html:match('<a[^>]+rel=["\']next["\'][^>]+href=["\']([^"\']+)')
        or html:match('<a[^>]+class=["\'][^"\']*next%-btn[^"\']*["\'][^>]+href=["\']([^"\']+)')

    return {
        title = Util.decodeHtml(Util.trim(title)),
        content = table.concat(paragraphs, "\n"),
        previous_url = previous_url and absolute(self.base_url, previous_url) or nil,
        next_url = next_url and absolute(self.base_url, next_url) or nil,
        url = chapter.url,
        kind = self.kind,
    }
end

function Source:getChapter(chapter)
    local html, err = Http:get(chapter.url, stdHeaders(self.base_url))
    if not html then
        return nil, err
    end
    return self:parseChapter(html, chapter)
end

return Source
