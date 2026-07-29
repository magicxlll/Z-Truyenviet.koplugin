local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local ko_util = require("util")

local Source = {
    id = "conduongbachu",
    name = "Con Đường Bá Chủ",
    kind = "text",
    base_url = "https://conduongbachu.com",
    -- The chapter selector on a chapter page is already ordered 1..N.
    reversed_chapters = false,
    _chapter_index = nil,
    _chapter_index_url = nil,
}

local PAGE_SIZE = 50
local CANONICAL_TITLE = "Con Đường Bá Chủ"

local function stdHeaders(base_url)
    return {
        ["Referer"] = base_url .. "/",
        ["Accept"] = "text/html,application/xhtml+xml",
    }
end

local function absolute(base_url, href)
    return Util.absoluteUrl(base_url, href)
end

local function parseChapterNumber(title, url)
    -- Several legacy posts use a slug one number behind the rendered title
    -- (for example slug `chuong-3055` is titled “Chương 3056”). The visible
    -- title is the authoritative chapter number.
    return tonumber((title or ""):match("(%d+)"))
        or tonumber((url or ""):match("/chuong%-(%d+)"))
end

local function chapterFromOption(base_url, href, raw_title, source_id)
    local url = absolute(base_url, href)
    local title = Util.trim(Util.stripTags(raw_title))
    title = Util.decodeHtml(title)
    if not url or url == "" or title == ""
            or not url:find(base_url, 1, true)
            or url:find("/chapter-truyen", 1, true)
            or url:find("#", 1, true) then
        return nil
    end
    local number = parseChapterNumber(title, url)
    if not number then
        return nil
    end
    return {
        title = title,
        url = url,
        number = number,
        order = number,
        source_id = source_id,
        story_url = base_url .. "/",
        kind = "text",
    }
end

local function uniqueChapters(chapters)
    local unique = {}
    local seen_numbers = {}
    for _, chapter in ipairs(chapters or {}) do
        if not seen_numbers[chapter.number] then
            seen_numbers[chapter.number] = true
            table.insert(unique, chapter)
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

local function parseChapterSelector(html, base_url, source_id)
    local chapters = {}
    local seen = {}
    for attrs, raw_title in html:gmatch(
        "<option([^>]*)>([%s%S]-)</option>"
    ) do
        local href = Util.getAttribute(attrs, "value")
        local chapter = href
            and chapterFromOption(base_url, href, raw_title, source_id)
        if chapter and not seen[chapter.url] then
            seen[chapter.url] = true
            table.insert(chapters, chapter)
        end
    end
    return uniqueChapters(chapters)
end

local function parseWpPosts(raw, base_url, source_id, json)
    local ok, posts = pcall(json.decode, raw)
    if not ok or type(posts) ~= "table" then
        return nil
    end
    local chapters = {}
    for _, post in ipairs(posts) do
        local title = post.title and post.title.rendered
        local chapter = post.link and title
            and chapterFromOption(base_url, post.link, title, source_id)
        if chapter then
            table.insert(chapters, chapter)
        end
    end
    return chapters
end

local function parseListingChapters(html, base_url, source_id)
    local chapters = {}
    local seen = {}
    for attrs, raw_title in html:gmatch(
        "<a([^>]*)>([%s%S]-)</a>"
    ) do
        local href = Util.getAttribute(attrs, "href")
        local chapter = href
            and chapterFromOption(base_url, href, raw_title, source_id)
        if chapter and not seen[chapter.url] then
            seen[chapter.url] = true
            table.insert(chapters, chapter)
        end
    end
    table.sort(chapters, function(a, b)
        return a.number > b.number
    end)
    return chapters
end

local function parseGenres(html, base_url)
    local genres = {}
    local seen = {}
    for href, name in html:gmatch(
        '<a[^>]+href=["\'](https?://conduongbachu%.com/[^"\']+)["\'][^>]*>([^<]+)</a>'
    ) do
        local clean_name = Util.trim(Util.decodeHtml(name))
        if clean_name ~= ""
                and not href:find("/chuong%-", 1, false)
                and not href:find("/chapter-truyen", 1, true)
                and not seen[href]
                and #clean_name < 80 then
            seen[href] = true
            table.insert(genres, {
                name = clean_name,
                url = href,
            })
        end
    end
    return genres
end

local function parseStory(html, base_url, source_id)
    local cover = html:match(
        '<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)'
    )
    local title = html:match(
        '<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)'
    ) or html:match("<title>([%s%S]-)</title>")
    title = title and Util.trim(Util.decodeHtml(title))
        or CANONICAL_TITLE
    title = title:gsub("%s*%-%s*Đọc truyện online%s*$", "")
    if title:lower():find("chapter truyện", 1, true) then
        title = CANONICAL_TITLE
    end
    return {
        source_id = source_id,
        title = title,
        url = base_url .. "/",
        cover_url = cover and absolute(base_url, cover) or nil,
        kind = "text",
    }
end

local function maxPage(html, fallback)
    local highest = tonumber(fallback) or 1
    for page in html:gmatch(
        "/chapter%-truyen/page/(%d+)/"
    ) do
        highest = math.max(highest, tonumber(page) or highest)
    end
    return highest
end

local function chapterIndex(self)
    if self._chapter_index and self._chapter_index_url == self.base_url then
        return self._chapter_index
    end

    local category_url = self.base_url .. "/chapter-truyen/"
    local listing_html, listing_err = Http:get(
        category_url,
        stdHeaders(self.base_url)
    )
    if not listing_html then
        return nil, "Không thể tải danh mục chương: " .. tostring(listing_err)
    end

    local latest_url = listing_html:match(
        'href=["\'](https?://conduongbachu%.com/chuong%-[^"\']+)["\']'
    )
    if not latest_url then
        return nil, "Không tìm thấy link chương mới nhất trên danh mục"
    end

    local latest_html, latest_err = Http:get(
        latest_url,
        stdHeaders(self.base_url)
    )
    if not latest_html then
        return nil, "Không thể tải trang chỉ mục chương: "
            .. tostring(latest_err)
    end

    local selector_chapters = parseChapterSelector(
        latest_html,
        self.base_url,
        self.id
    )
    if #selector_chapters == 0 then
        return nil, "Chỉ mục chương rỗng hoặc website đã đổi cấu trúc"
    end
    local chapters = selector_chapters
    local json_ok, json = pcall(require, "json")
    if json_ok and json then
        local api_url = self.base_url
            .. "/wp-json/wp/v2/posts?categories=3&per_page=100"
            .. "&_fields=link,title&page=1"
        local raw, api_err, headers = Http:get(
            api_url,
            stdHeaders(self.base_url)
        )
        if raw then
            local api_chapters = parseWpPosts(
                raw,
                self.base_url,
                self.id,
                json
            )
            local total_api_pages = headers
                and tonumber(
                    headers["x-wp-totalpages"]
                        or headers["X-WP-TotalPages"]
                )
            if api_chapters and total_api_pages then
                for api_page = 2, total_api_pages do
                    local page_raw, page_err = Http:get(
                        self.base_url
                            .. "/wp-json/wp/v2/posts?categories=3"
                            .. "&per_page=100&_fields=link,title&page="
                            .. api_page,
                        stdHeaders(self.base_url)
                    )
                    if not page_raw then
                        return nil, "Không thể tải chỉ mục WordPress trang "
                            .. api_page .. ": " .. tostring(page_err)
                    end
                    local page_chapters = parseWpPosts(
                        page_raw,
                        self.base_url,
                        self.id,
                        json
                    )
                    if not page_chapters then
                        return nil, "WordPress trả JSON chương không hợp lệ"
                    end
                    for _, chapter in ipairs(page_chapters) do
                        table.insert(api_chapters, chapter)
                    end
                end
                chapters = uniqueChapters(api_chapters)
            end
        elseif api_err then
            -- The HTML selector remains a compatible fallback if REST API is
            -- disabled by a host or a proxy.
        end
    end
    self._chapter_index = chapters
    self._chapter_index_url = self.base_url
    return chapters
end

function Source:parseSearch(html)
    if not html:find(
        '<h2[^>]-class=["\'][^"\']*entry%-title',
        1
    ) then
        return {}
    end
    return {
        {
            source_id = self.id,
            title = CANONICAL_TITLE,
            url = self.base_url .. "/",
            cover_url = html:match(
                '<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)'
            ),
            kind = self.kind,
        },
    }
end

function Source:search(query)
    local encoded = ko_util.urlEncode(query or "")
    local html, err = Http:get(
        self.base_url .. "/?s=" .. encoded,
        stdHeaders(self.base_url)
    )
    if not html then
        return nil, err
    end
    return self:parseSearch(html)
end

function Source:getCompleted(page)
    page = page or 1
    local url = self.base_url .. "/chapter-truyen/"
    if page > 1 then
        url = url .. "page/" .. page .. "/"
    end
    local html, err = Http:get(url, stdHeaders(self.base_url))
    if not html then
        return nil, err
    end

    local story = parseStory(html, self.base_url, self.id)
    return {
        stories = { story },
        genres = parseGenres(html, self.base_url),
        page = page,
        total_pages = 1,
        title = "Con Đường Bá Chủ",
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
    local html, err = Http:get(story.url or (self.base_url .. "/"), stdHeaders(self.base_url))
    if not html then
        return nil, err
    end
    local description = html:match(
        '<meta[^>]+name=["\']description["\'][^>]+content=["\']([^"\']+)'
    )
    local author = html:match("[Tt]ác giả%s+([%aÀ-ỹ][^<,%.]+)")
        or "Akay Hau"
    local genres = {}
    for _, genre in ipairs(parseGenres(html, self.base_url)) do
        table.insert(genres, genre.name)
    end
    return {
        description = description and Util.decodeHtml(description) or "",
        author = Util.trim(Util.decodeHtml(author)),
        status = "Đang cập nhật",
        genres = genres,
    }
end

function Source:getStoryPage(story, page)
    page = math.max(1, tonumber(page) or 1)
    local chapters, err = chapterIndex(self)
    if not chapters then
        return nil, err
    end

    local total_pages = math.max(1, math.ceil(#chapters / PAGE_SIZE))
    if page > total_pages then
        return nil, string.format(
            "Trang chương %d vượt quá tổng số trang %d",
            page,
            total_pages
        )
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
    local chapters, err = chapterIndex(self)
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

    local title_html = html:match(
        '<h1[^>]-class=["\'][^"\']*entry%-title[^"\']*["\'][^>]*>([%s%S]-)</h1>'
    ) or html:match("<h1[^>]*>([%s%S]-)</h1>")
    local title = title_html and Util.stripTags(title_html)
        or chapter.title

    local entry_start = html:find(
        '<div[^>]-class=["\'][^"\']*entry%-content[^"\']*single%-page',
        1
    )
    local nav_start = entry_start and html:find(
        '<nav[^>]-id=["\']nav%-below["\']',
        entry_start
    )
    local region = entry_start
        and html:sub(entry_start, (nav_start or #html + 1) - 1)
        or html
    local paragraphs = {}
    for attrs, raw_body in region:gmatch(
        "<p([^>]*)>([%s%S]-)</p>"
    ) do
        local text = Util.trim(Util.stripTags(raw_body))
        if text ~= "" and not isNoiseParagraph(attrs, text) then
            table.insert(paragraphs, "<p>" .. raw_body .. "</p>")
        end
    end
    if #paragraphs == 0 then
        return nil, "Không tìm thấy nội dung chương"
    end

    local previous_url = html:match(
        '<a[^>]+rel=["\']prev["\'][^>]+href=["\']([^"\']+)'
    ) or html:match(
        '<a[^>]+class=["\'][^"\']*prev%-btn[^"\']*["\'][^>]+href=["\']([^"\']+)'
    )
    local next_url = html:match(
        '<a[^>]+rel=["\']next["\'][^>]+href=["\']([^"\']+)'
    ) or html:match(
        '<a[^>]+class=["\'][^"\']*next%-btn[^"\']*["\'][^>]+href=["\']([^"\']+)'
    )
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
