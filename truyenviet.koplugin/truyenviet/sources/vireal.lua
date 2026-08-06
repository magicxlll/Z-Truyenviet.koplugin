local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local ko_util = require("util")

-- Vireal.vn — Trang đọc truyện Next.js RSC với Anti-scraping CSS Obfuscation
local Source = {
    id = "vireal",
    name = "Vireal",
    kind = "text",
    base_url = "https://vireal.vn",
}

local function normalizeHtml(raw_html)
    if not raw_html then return "" end
    return raw_html:gsub('\\"', '"'):gsub("\\/", "/"):gsub("\\\\", "\\")
end

local function cleanVirealContent(raw_chunk)
    if not raw_chunk then return "" end

    -- 1. Giải mã Unicode escape sequences \u00xx
    local chunk = raw_chunk:gsub('\\u(%x%x%x%x)', function(hex)
        local code = tonumber(hex, 16)
        if code then
            if code == 60 then return "<"
            elseif code == 62 then return ">"
            elseif code == 34 then return '"'
            elseif code == 39 then return "'"
            elseif code == 38 then return "&"
            elseif utf8 and utf8.char then
                local ok, ch = pcall(utf8.char, code)
                if ok then return ch end
            end
        end
        return ""
    end)
    chunk = chunk:gsub('\\"', '"'):gsub('\\/', '/'):gsub('\\\\', '\\')

    -- 2. Xóa các khối style bọc trong nội dung
    chunk = chunk:gsub('<style[^>]*>.-</style>', '')

    -- 3. Xóa các thẻ nhúng từ ảo ẩn anti-scraping chứa text-indent hoặc font-size: 0
    chunk = chunk:gsub('<([%a%d]+)[^>]*style="[^"]*text%-indent:[^"]*"[^>]*>.-</%1>', '')
    chunk = chunk:gsub('<([%a%d]+)[^>]*style="[^"]*font%-size:%s*0[^"]*"[^>]*>.-</%1>', '')
    chunk = chunk:gsub('<([%a%d]+)[^>]*style="[^"]*display:%s*none[^"]*"[^>]*>.-</%1>', '')

    -- 4. Bóc tách các thẻ rác 6-8 ký tự ngẫu nhiên bọc từ thực, chỉ giữ thẻ <p>, <br>
    chunk = chunk:gsub('</?[%a%d]+[^>]*>', function(tag)
        local lower = tag:lower()
        if lower:sub(1, 3) == "<p>" or lower:sub(1, 4) == "<p " or lower:sub(1, 4) == "</p>" or lower:sub(1, 4) == "<br" then
            return tag
        end
        return ""
    end)

    -- 5. Làm sạch thẻ đoạn văn <p>
    chunk = chunk:gsub('<p[^>]*>', '<p>'):gsub('%s*</p>', '</p>')
    chunk = chunk:gsub('&nbsp;', ' ')

    return Util.sanitizeContentHtml(chunk)
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
        html, err = Http:get(self.base_url, {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        })
    end
    if not html then return nil, err end

    html = normalizeHtml(html)
    local stories = {}
    local seen = {}

    -- Match title & slug directly from Next.js RSC state
    for title, slug in html:gmatch('"name"%s*:%s*"([^"]+)"[^{}]*"slug"%s*:%s*"([%w%-]+)"') do
        if not seen[slug] and #slug > 3 and not slug:find("chuong") and not slug:find("chapter") then
            seen[slug] = true
            table.insert(stories, {
                source_id = self.id,
                title = Util.decodeHtml(Util.stripTags(title)),
                url = self.base_url .. "/story/" .. slug,
                cover_url = nil,
                kind = "text",
            })
        end
    end

    -- Fallback matching by URL path
    if #stories == 0 then
        for slug in html:gmatch('/story/([%w%-]+)') do
            if not seen[slug] and #slug > 3 then
                seen[slug] = true
                table.insert(stories, {
                    source_id = self.id,
                    title = "Vireal · " .. slug,
                    url = self.base_url .. "/story/" .. slug,
                    cover_url = nil,
                    kind = "text",
                })
            end
        end
    end

    return stories
end

function Source:getCompleted(page)
    local res = self:search("")
    return {
        stories = res or {},
        genres = self:getGenresList(),
        page = page or 1,
        total_pages = 1,
        title = "Truyện Mới Cập Nhật",
    }
end

function Source:getHot(page)
    return self:getCompleted(page)
end

function Source:getUpdating(page)
    return self:getCompleted(page)
end

function Source:getGenresList()
    return {
        { name = "🔥 Truyện Hot / Đề Cử", section = "hot", url = self.base_url },
        { name = "✅ Truyện Hoàn Thành (Full)", section = "completed", url = self.base_url },
        { name = "🆕 Truyện Đang Ra / Cập Nhật Mới", section = "updating", url = self.base_url },
    }
end

function Source:getGenre(genre, page)
    return self:getCompleted(page)
end

function Source:getStoryDetails(story)
    return {
        title = story.title,
        description = "Truyện đọc tại Vireal.vn",
        author = "Đang cập nhật",
        status = "Đang cập nhật",
        genres = {},
        cover_url = story.cover_url,
    }
end

function Source:getStoryPage(story, page)
    local story_url = story.url:gsub("%?.*$", "")
    local html, err = Http:get(story_url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not html then return nil, err end

    html = normalizeHtml(html)
    local chapters = {}
    local seen = {}

    for slug in html:gmatch('/story/[%w%-]+/([%w%-]+)') do
        if not seen[slug] and (slug:find("chuong") or slug:find("chapter") or slug:match("^%d+$")) then
            seen[slug] = true
            local num = tonumber(slug:match("%d+")) or #chapters + 1
            table.insert(chapters, {
                title = "Chương " .. num,
                url = story_url .. "/" .. slug,
                number = num,
                order = num,
                source_id = self.id,
                story_url = story.url,
                kind = self.kind,
            })
        end
    end

    table.sort(chapters, function(a, b) return a.number < b.number end)

    return {
        story = story,
        chapters = chapters,
        page = 1,
        total_pages = 1,
    }
end

function Source:getAllChapters(story)
    local res = self:getStoryPage(story, 1)
    return res and res.chapters or {}
end

function Source:getChapter(chapter)
    local html, err = Http:get(chapter.url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not html then return nil, err end

    html = normalizeHtml(html)
    local title = html:match('<h1[^>]*>([%s%S]-)</h1>') or chapter.title
    local content = cleanVirealContent(html)

    return {
        title = Util.trim(Util.stripTags(title)),
        content = content,
        url = chapter.url,
        kind = self.kind,
    }
end

return Source
