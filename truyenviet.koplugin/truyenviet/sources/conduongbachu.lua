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
    _chapter_pages = {},
}

local PAGE_SIZE = 50
local REST_PAGE_SIZE = 100
local MAX_REST_PAGES = 100

local STORIES = {
    {
        id = "main",
        cat_id = 3,
        title = "Con Đường Bá Chủ (Chính Truyện)",
        url = "https://conduongbachu.com/",
        slug = "chapter-truyen",
        all_posts_are_chapters = true,
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
        cover_url = "https://conduongbachu.com/wp-content/uploads/2025/04/conduongbachu-ngoai-truyen-268x400.jpg",
    },
    {
        id = "chua-te-chi-lo",
        cat_id = 15,
        title = "Ngoại Truyện: Chúa Tể Chi Lộ",
        url = "https://conduongbachu.com/ngoai-truyen-chua-te-chi-lo/",
        slug = "ngoai-truyen-chua-te-chi-lo",
        cover_url = "https://conduongbachu.com/wp-content/uploads/2025/04/conduongbachu-ngoai-truyen-268x400.jpg",
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
    local target_url = type(story_or_url) == "table" and (story_or_url.url or story_or_url.story_url) or tostring(story_or_url or "")
    target_url = target_url:gsub("%?.*$", ""):gsub("/$", "") .. "/"

    -- 1. Ưu tiên khớp chính xác theo URL trước
    for _, config in ipairs(STORIES) do
        local config_url = config.url:gsub("/$", "") .. "/"
        if target_url == config_url then
            return config
        end
    end

    -- 2. Khớp slug từ chuỗi dài nhất tới ngắn nhất (tránh ngoai-truyen ăn nhầm ngoai-truyen-chua-te-chi-lo)
    local sorted = {}
    for _, config in ipairs(STORIES) do
        table.insert(sorted, config)
    end
    table.sort(sorted, function(a, b) return #a.slug > #b.slug end)

    for _, config in ipairs(sorted) do
        if target_url:find(config.slug, 1, true) then
            return config
        end
    end

    return STORIES[1]
end

local function parseChapterNumber(title, url)
    return tonumber((title or ""):match("[Cc][Hh]ƯƠ[Nn][Gg]%s*(%d+)"))
        or tonumber((title or ""):match("[Cc]hương%s*(%d+)"))
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
        return Util.naturalCompare(a.title or a.url, b.title or b.url)
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

        -- Bỏ bài không phải chương (ví dụ "Bầu chọn ngoại truyện"), nhưng
        -- vẫn giữ slug legacy như /3399-vo-de/ với tiêu đề "3399: VÔ ĐỀ.".
        local starts_with_number =
            title:match("^%s*%d+%s*[:%-%.]") ~= nil
        if link and title ~= "" and (
                title:find("Chương")
                or title:find("CHƯƠNG")
                or link:find("/chuong-", 1, true)
                or starts_with_number
            ) then
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
    return chapters, #posts
end

local function responseHeader(headers, wanted)
    wanted = wanted:lower()
    for name, value in pairs(headers or {}) do
        if tostring(name):lower() == wanted then
            return value
        end
    end
    return nil
end

local function wpApiUrl(self, config, api_page)
    return self.base_url
        .. "/wp-json/wp/v2/posts?categories=" .. config.cat_id
        .. "&per_page=" .. REST_PAGE_SIZE
        .. "&_fields=link,title&page=" .. api_page
        .. "&order=asc&orderby=date"
end

local function requestWpPage(self, config, api_page)
    local api_url = wpApiUrl(self, config, api_page)
    local raw_json, request_err, response_headers, status =
        Http:get(api_url, stdHeaders(self.base_url))

    if not raw_json or raw_json == "" then
        return nil, string.format(
            "Không thể tải mục lục WordPress trang %d: %s",
            api_page,
            tostring(request_err or "phản hồi rỗng")
        )
    end
    if tonumber(status) and tonumber(status) >= 400 then
        return nil, string.format(
            "Không thể tải mục lục WordPress trang %d: HTTP %s",
            api_page,
            tostring(status)
        )
    end
    if raw_json:find('"code":', 1, true) then
        return nil, string.format(
            "WordPress trả lỗi ở trang mục lục %d",
            api_page
        )
    end

    local chapters, raw_post_count = parseWpPosts(
        raw_json,
        self.base_url,
        self.id,
        config.url
    )
    if not chapters then
        return nil, string.format(
            "Dữ liệu mục lục WordPress trang %d không hợp lệ",
            api_page
        )
    end

    local total_posts = tonumber(responseHeader(response_headers, "x-wp-total"))
    local total_api_pages =
        tonumber(responseHeader(response_headers, "x-wp-totalpages"))

    if not total_api_pages and raw_post_count < REST_PAGE_SIZE then
        total_api_pages = api_page
    end
    if not total_posts and total_api_pages == api_page then
        total_posts = (api_page - 1) * REST_PAGE_SIZE + raw_post_count
    end

    return {
        chapters = chapters,
        raw_post_count = raw_post_count,
        total_posts = total_posts,
        total_api_pages = total_api_pages,
        api_page = api_page,
    }
end

local function cachedWpPage(self, config, api_page)
    self._chapter_pages[config.id] = self._chapter_pages[config.id] or {}
    local cached = self._chapter_pages[config.id][api_page]
    if cached then
        return cached
    end

    local result, err = requestWpPage(self, config, api_page)
    if not result then
        return nil, err
    end
    self._chapter_pages[config.id][api_page] = result
    return result
end

local function completeChapterIndex(self, story)
    local config = detectStoryConfig(story)
    if self._chapter_index[config.id] then
        return self._chapter_index[config.id]
    end

    local first, first_err = cachedWpPage(self, config, 1)
    if not first then
        return nil, first_err
    end

    local total_api_pages = first.total_api_pages
    if not total_api_pages then
        return nil, "WordPress không trả tổng số trang mục lục"
    end
    if total_api_pages < 1 or total_api_pages > MAX_REST_PAGES then
        return nil, string.format(
            "Tổng số trang mục lục WordPress không hợp lệ: %s",
            tostring(total_api_pages)
        )
    end

    local chapters = {}
    local raw_post_count = 0
    for api_page = 1, total_api_pages do
        local page_data, page_err = cachedWpPage(self, config, api_page)
        if not page_data then
            return nil, page_err
        end
        raw_post_count = raw_post_count + page_data.raw_post_count
        for _, chapter in ipairs(page_data.chapters) do
            chapters[#chapters + 1] = chapter
        end
    end

    if first.total_posts and raw_post_count ~= first.total_posts then
        return nil, string.format(
            "Mục lục chưa đủ: nhận %d/%d bài WordPress",
            raw_post_count,
            first.total_posts
        )
    end

    chapters = uniqueChapters(chapters)
    if config.all_posts_are_chapters
            and first.total_posts
            and #chapters ~= first.total_posts then
        return nil, string.format(
            "Mục lục chính truyện thiếu: nhận %d/%d chương",
            #chapters,
            first.total_posts
        )
    end
    self._chapter_index[config.id] = chapters
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
    local config = detectStoryConfig(story)
    local page_chapters = {}

    local complete = self._chapter_index[config.id]
    local total_pages
    if complete then
        total_pages = math.max(1, math.ceil(#complete / PAGE_SIZE))
        page = math.min(page, total_pages)
        local first = (page - 1) * PAGE_SIZE + 1
        for index = first, math.min(#complete, first + PAGE_SIZE - 1) do
            page_chapters[#page_chapters + 1] = complete[index]
        end
    else
        local api_page = math.floor((page - 1) / 2) + 1
        local page_data, page_err = cachedWpPage(self, config, api_page)
        if not page_data then
            return nil, page_err
        end
        if not page_data.total_posts then
            return nil, "WordPress không trả tổng số bài chương"
        end

        total_pages = math.max(
            1,
            math.ceil(page_data.total_posts / PAGE_SIZE)
        )
        page = math.min(page, total_pages)
        local offset = ((page - 1) % 2) * PAGE_SIZE
        local normalized = uniqueChapters(page_data.chapters)
        for index = offset + 1, math.min(#normalized, offset + PAGE_SIZE) do
            page_chapters[#page_chapters + 1] = normalized[index]
        end
    end

    local copied_chapters = {}
    for _, chapter in ipairs(page_chapters) do
        local copy = {}
        for key, value in pairs(chapter) do
            copy[key] = value
        end
        copy.story_url = story.url
        copied_chapters[#copied_chapters + 1] = copy
    end

    story.details = story.details or self:getStoryDetails(story)
    return {
        story = story,
        chapters = copied_chapters,
        page = page,
        total_pages = total_pages,
    }
end

function Source:getAllChapters(story)
    local chapters, err = completeChapterIndex(self, story)
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
