local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local ko_util = require("util")

-- MeTruyenChuVN.org — Đọc Truyện Chữ Online
local Source = {
    id = "metruyenchuvn",
    name = "Mê Truyện Chữ VN",
    kind = "text",
    base_url = "https://metruyenchuvn.org",
}

local function normalizeHtml(raw_html)
    if not raw_html then return "" end
    local s = raw_html:gsub('\\u003c', '<'):gsub('\\u003e', '>'):gsub('\\u0027', "'"):gsub('\\u0022', '"')
    return s:gsub('\\"', '"'):gsub("\\/", "/"):gsub("\\\\", "\\")
end

local function isValidStoryPath(path)
    if not path or #path < 3 or path == "/" then return false end
    local lower = path:lower()
    if lower:find("^/danh%-sach") or lower:find("^/the%-loai") or lower:find("^/tac%-gia")
        or lower:find("^/chuong%-") or lower:find("^/search") or lower:find("^/tim%-kiem")
        or lower:find("^/contact") or lower:find("^/policy") or lower:find("^/dmca")
        or lower:find("^/about") or lower:find("^/privacy") or lower:find("^/terms")
        or lower:find("^/user") or lower:find("^/login") or lower:find("^/register")
        or lower:find("^/history") or lower:find("^/images") or lower:find("^/theme")
        or lower:find("^/tos") or lower:find("^/favicon") then
        return false
    end
    return lower:find("^/[%w%-]+/?$") ~= nil
end

function Source:search(query)
    local html, err
    if query and query ~= "" then
        local encoded = ko_util.urlEncode(query):gsub("%%20", "+")
        local url = self.base_url .. "/search?q=" .. encoded
        html, err = Http:get(url, {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        })
    end

    if not html or #html < 500 then
        html, err = Http:get(self.base_url .. "/", {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        })
    end
    if not html then return nil, err end

    html = normalizeHtml(html)
    local stories = {}
    local seen = {}

    for href, title in html:gmatch('<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>') do
        local path = href:gsub("^https?://[^/]+", "")
        if isValidStoryPath(path) and not seen[path] then
            seen[path] = true
            local full_url = Util.absoluteUrl(self.base_url, path)
            table.insert(stories, {
                source_id = self.id,
                title = Util.decodeHtml(Util.trim(title)),
                url = full_url,
                cover_url = nil,
                kind = "text",
            })
        end
    end

    return stories
end

function Source:getCompleted(page)
    page = page or 1
    local url = self.base_url .. "/danh-sach/truyen-full/?page=" .. page
    local html, err = Http:get(url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not html then
        url = self.base_url .. "/"
        html, err = Http:get(url)
    end
    if not html then return nil, err end

    html = normalizeHtml(html)
    local stories = {}
    local seen = {}

    for href, title in html:gmatch('<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>') do
        local path = href:gsub("^https?://[^/]+", "")
        if isValidStoryPath(path) and not seen[path] then
            seen[path] = true
            local full_url = Util.absoluteUrl(self.base_url, path)
            table.insert(stories, {
                source_id = self.id,
                title = Util.decodeHtml(Util.trim(title)),
                url = full_url,
                cover_url = nil,
                kind = "text",
            })
        end
    end

    return {
        stories = stories,
        genres = {},
        page = page,
        total_pages = Util.maxPage(html, page),
        title = "Truyện hoàn thành",
    }
end

function Source:getHot(page)
    page = page or 1
    local url = self.base_url .. "/danh-sach/truyen-hot/?page=" .. page
    local html, err = Http:get(url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not html then
        return self:getCompleted(page)
    end

    html = normalizeHtml(html)
    local stories = {}
    local seen = {}

    for href, title in html:gmatch('<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>') do
        local path = href:gsub("^https?://[^/]+", "")
        if isValidStoryPath(path) and not seen[path] then
            seen[path] = true
            local full_url = Util.absoluteUrl(self.base_url, path)
            table.insert(stories, {
                source_id = self.id,
                title = Util.decodeHtml(Util.trim(title)),
                url = full_url,
                cover_url = nil,
                kind = "text",
            })
        end
    end

    return {
        stories = stories,
        genres = {},
        page = page,
        total_pages = Util.maxPage(html, page),
        title = "Truyện Hot / Đề Cử",
    }
end

function Source:getUpdating(page)
    page = page or 1
    local url = self.base_url .. "/danh-sach/truyen-moi/?page=" .. page
    local html, err = Http:get(url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not html then
        return self:getCompleted(page)
    end

    html = normalizeHtml(html)
    local stories = {}
    local seen = {}

    for href, title in html:gmatch('<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>') do
        local path = href:gsub("^https?://[^/]+", "")
        if isValidStoryPath(path) and not seen[path] then
            seen[path] = true
            local full_url = Util.absoluteUrl(self.base_url, path)
            table.insert(stories, {
                source_id = self.id,
                title = Util.decodeHtml(Util.trim(title)),
                url = full_url,
                cover_url = nil,
                kind = "text",
            })
        end
    end

    return {
        stories = stories,
        genres = {},
        page = page,
        total_pages = Util.maxPage(html, page),
        title = "Truyện Mới Cập Nhật",
    }
end

function Source:getSections()
    return {
        { id = "hot", name = "🔥 Truyện Hot / Đề Cử" },
        { id = "completed", name = "✅ Truyện Hoàn Thành (Full)" },
        { id = "updating", name = "🆕 Truyện Đang Ra / Cập Nhật Mới" },
        { id = "search", name = "🔍 Tìm Kiếm Trên Mê Truyện Chữ" },
    }
end

function Source:getGenre(genre, page)
    page = page or 1
    local raw_url = genre and (genre.url or genre.path)
    if not raw_url then
        return self:getCompleted(page)
    end
    local abs_url = Util.absoluteUrl(self.base_url, raw_url)
    local url = abs_url .. (abs_url:find("%?") and "&" or "?") .. "page=" .. page
    local html, err = Http:get(url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not html then return self:getCompleted(page) end

    html = normalizeHtml(html)
    local stories = {}
    local seen = {}

    for href, title in html:gmatch('<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>') do
        local path = href:gsub("^https?://[^/]+", "")
        if isValidStoryPath(path) and not seen[path] then
            seen[path] = true
            local full_url = Util.absoluteUrl(self.base_url, path)
            table.insert(stories, {
                source_id = self.id,
                title = Util.decodeHtml(Util.trim(title)),
                url = full_url,
                cover_url = nil,
                kind = "text",
            })
        end
    end

    return {
        stories = stories,
        genres = {},
        page = page,
        total_pages = Util.maxPage(html, page),
        title = genre and genre.name or "Thể loại",
    }
end

function Source:getStoryDetails(story)
    local html, err = Http:get(story.url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not html then return nil, err end

    html = normalizeHtml(html)

    local title = html:match('<meta property="og:title" content="([^"]+)"')
        or html:match('<h1[^>]*>([^<]+)</h1>')
        or story.title

    local author = html:match('<a[^>]+href="/tac-gia/[^"]*"[^>]*>([^<]+)</a>') or "Đang cập nhật"
    local desc = html:match('<div[^>]+id="book_desc"[^>]*>(.-)</div>')
        or html:match('<div[^>]+class="[^"]*desc[^"]*"[^>]*>(.-)</div>')
    local cover = html:match('<meta property="og:image" content="([^"]+)"')
        or html:match('<img[^>]+src="([^"]+)"[^>]*class="[^"]*cover[^"]*"')

    return {
        title = Util.decodeHtml(Util.trim(title)),
        author = Util.trim(author),
        description = desc and Util.stripTags(desc) or "Truyện đọc tại MeTruyenChuVN.org",
        cover_url = cover and Util.absoluteUrl(self.base_url, cover) or story.cover_url,
        genres = {},
    }
end

function Source:getStoryPage(story, page)
    local story_url = story.url:gsub("%?.*$", "")
    local html, err = Http:get(story_url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not html then return nil, err end

    html = normalizeHtml(html)
    local story_id = html:match("page%s*%(%s*(%d+)")
        or html:match("data%-id=[\"'](%d+)[\"']")
        or html:match("id=[\"']book_id[\"']%s*value=[\"'](%d+)[\"']")

    local chapters = {}
    local seen = {}

    if story_id then
        local page_num = 1
        while page_num <= 50 do
            local api_url = self.base_url .. "/get/listchap/" .. story_id .. "?page=" .. page_num
            local json_str, api_err = Http:get(api_url, {
                ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
            })
            if not json_str or #json_str < 30 then break end
            
            json_str = normalizeHtml(json_str)
            local found_count = 0
            for chap_url, chap_title in json_str:gmatch('<a[^>]+href=[\'"]([^\'"]+)[\'"][^>]*>([%s%S]-)</a>') do
                if not seen[chap_url] then
                    seen[chap_url] = true
                    found_count = found_count + 1
                    local full_chap_url = Util.absoluteUrl(self.base_url, chap_url)
                    table.insert(chapters, {
                        title = Util.decodeHtml(Util.stripTags(chap_title)),
                        url = full_chap_url,
                        source_id = self.id,
                        story_url = story.url,
                        kind = "text",
                    })
                end
            end

            if found_count == 0 then break end
            page_num = page_num + 1
        end
    end

    if #chapters == 0 then
        for chap_url, chap_title in html:gmatch('<a[^>]+href=[\'"]([^\'"]+)[\'"][^>]*>([%s%S]-)</a>') do
            if chap_url:find("/chuong-") or chap_url:find("/chapter-") then
                if not seen[chap_url] then
                    seen[chap_url] = true
                    local full_chap_url = Util.absoluteUrl(self.base_url, chap_url)
                    table.insert(chapters, {
                        title = Util.decodeHtml(Util.stripTags(chap_title)),
                        url = full_chap_url,
                        source_id = self.id,
                        story_url = story.url,
                        kind = "text",
                    })
                end
            end
        end
    end

    story.details = self:getStoryDetails(story)
    return {
        story = story,
        chapters = chapters,
        page = 1,
        total_pages = 1,
    }
end

function Source:getChapter(chapter)
    local html, err = Http:get(chapter.url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not html then return nil, err end

    html = normalizeHtml(html)
    local title = html:match('<h2[^>]*class="[^"]*current%-chapter[^"]*"[^>]*>([%s%S]-)</h2>')
        or html:match('<h1[^>]*>([^<]+)</h1>')
        or chapter.title

    local content = html:match('<div[^>]-class="[^"]*truyen[^"]*"[^>]*>(.-)</div>%s*</div>%s*<div')
        or html:match('<div[^>]-class="[^"]*truyen[^"]*"[^>]*>(.-)<footer')
        or html:match('<div[^>]-class="[^"]*truyen[^"]*"[^>]*>(.+)</div>')

    if not content or #Util.stripTags(content) < 50 then
        return nil, "Không tìm thấy nội dung chương từ MeTruyenChuVN"
    end

    return {
        title = Util.decodeHtml(Util.stripTags(title)),
        content = Util.sanitizeContentHtml(content),
        chapter_url = chapter.url,
        story_url = chapter.story_url,
    }
end

return Source
