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
            if not seen[slug] and #slug > 3 and not slug:find("chuong") and not slug:find("chapter") then
                seen[slug] = true
                table.insert(stories, {
                    source_id = self.id,
                    title = slug:gsub("%-", " "):gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest:lower() end),
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
    return {
        stories = self:search(""),
        genres = {},
        page = page or 1,
        total_pages = 1,
        title = "Truyện mới nhất",
    }
end

function Source:getHot(page)
    local res = self:search("")
    return {
        stories = res or {},
        genres = {},
        page = page or 1,
        total_pages = 1,
        title = "Truyện Hot / Đề Cử",
    }
end

function Source:getUpdating(page)
    local res = self:search("")
    return {
        stories = res or {},
        genres = {},
        page = page or 1,
        total_pages = 1,
        title = "Truyện Mới Cập Nhật",
    }
end

function Source:getSections()
    return {
        { id = "hot", name = "🔥 Truyện Hot / Đề Cử" },
        { id = "completed", name = "✅ Truyện Hoàn Thành (Full)" },
        { id = "updating", name = "🆕 Truyện Đang Ra / Cập Nhật Mới" },
        { id = "search", name = "🔍 Tìm Kiếm Trên Vireal" },
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
    local story_slug = story_url:match("/story/([^/?]+)") or ""

    local chapters = {}
    local seen = {}

    for name, slug in html:gmatch('"name"%s*:%s*"([^"]+)"%s*,%s*"slug"%s*:%s*"([^"]+)"') do
        if not seen[slug] and (slug:find("chuong") or slug:find("chapter") or name:find("Chương")) then
            seen[slug] = true
            local chap_url = self.base_url .. "/story/" .. story_slug .. "/" .. slug
            table.insert(chapters, {
                title = Util.decodeHtml(Util.stripTags(name)),
                url = chap_url,
                source_id = self.id,
                story_url = story.url,
                kind = "text",
            })
        end
    end

    if #chapters == 0 then
        for slug in html:gmatch('(chuong%-[%a%d%-]+)') do
            if not seen[slug] then
                seen[slug] = true
                local chap_url = self.base_url .. "/story/" .. story_slug .. "/" .. slug
                table.insert(chapters, {
                    title = slug:gsub("%-", " "),
                    url = chap_url,
                    source_id = self.id,
                    story_url = story.url,
                    kind = "text",
                })
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
    local raw_html, err = Http:get(chapter.url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    })
    if not raw_html then return nil, err end

    local norm_html = normalizeHtml(raw_html)
    local title = norm_html:match('"name"%s*:%s*"([^"]-Chương[^"]-)"') or chapter.title

    local pos = raw_html:find('\\u003cp') or raw_html:find('<p translate=') or raw_html:find('<p>')
    if not pos then
        return nil, "Không tìm thấy nội dung chương từ Vireal"
    end

    local chunk = raw_html:sub(pos, pos + 250000)
    local end_pos = chunk:find('</script>') or #chunk
    chunk = chunk:sub(1, end_pos)

    local content = cleanVirealContent(chunk)
    if not content or #content < 50 then
        return nil, "Nội dung chương Vireal quá ngắn hoặc bị lỗi"
    end

    return {
        title = title,
        content = content,
        chapter_url = chapter.url,
        story_url = chapter.story_url,
    }
end

return Source
