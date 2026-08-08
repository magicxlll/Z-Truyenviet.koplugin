local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local ko_util = require("util")

local Source = {
    id = "xtruyen",
    name = "XTruyen",
    kind = "text",
    base_url = "https://xtruyen.vn",
}

function Source:getCoverHeaders()
    return {
        ["Referer"] = self.base_url .. "/",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    }
end

function Source:parseSearch(html)
    local stories = {}
    for block in html:gmatch('<div class="popular%-item%-wrap">.-</div>%s*</div>') do
        local href = block:match('<h5 class="widget%-title"[^>]*>.-<a[^>]-href="([^"]+)"')
        local title = block:match('<h5 class="widget%-title"[^>]*>.-<a[^>]*>([^<]+)</a>')
        local cover = block:match('<img[^>]-src="([^"]+)"')
        
        if href and title then
            title = Util.trim(Util.stripTags(title))
            table.insert(stories, {
                source_id = self.id,
                title = Util.decodeHtml(title),
                url = Util.absoluteUrl(self.base_url, href),
                cover_url = cover and Util.absoluteUrl(self.base_url, cover) or nil,
                kind = self.kind,
            })
        end
    end
    return Util.uniqueBy(stories, "url")
end

function Source:search(query)
    local encoded = ko_util.urlEncode(query):gsub("%%20", "+")
    local url = self.base_url .. "/?s=" .. encoded .. "&post_type=wp-manga"
    local html, err = Http:get(url, self:getCoverHeaders())
    if not html then return nil, err end
    return self:parseSearch(html)
end

function Source:parseListing(html, page)
    return {
        stories = self:parseSearch(html),
        page = page or 1,
        total_pages = Util.maxPage(html, page),
    }
end

function Source:getCompleted(page)
    page = page or 1
    local url = self.base_url .. "/truyen/?m_orderby=trending&status=end&page=" .. page
    local html, err = Http:get(url, self:getCoverHeaders())
    if not html then return nil, err end
    local result = self:parseListing(html, page)
    result.title = "Truyện Hoàn Thành"
    return result
end

function Source:getHot(page)
    page = page or 1
    local url = self.base_url .. "/truyen/?m_orderby=trending&page=" .. page
    local html, err = Http:get(url, self:getCoverHeaders())
    if not html then return nil, err end
    local result = self:parseListing(html, page)
    result.title = "Truyện HOT"
    return result
end

function Source:getUpdating(page)
    page = page or 1
    local url = self.base_url .. "/truyen/?m_orderby=latest&page=" .. page
    local html, err = Http:get(url, self:getCoverHeaders())
    if not html then return nil, err end
    local result = self:parseListing(html, page)
    result.title = "Mới Cập Nhật"
    return result
end

function Source:getSections()
    return {
        { id = "updating", name = "🆕 Mới Cập Nhật" },
        { id = "hot", name = "🔥 Truyện HOT" },
        { id = "completed", name = "✅ Hoàn Thành" },
        { id = "search", name = "🔍 Tìm Kiếm" },
    }
end

function Source:parseStoryDetails(html)
    local description = html:match('<div class="summary__content[^"]*">(.-)</div>')
        or html:match('<div class="description[^"]*">(.-)</div>')
        or Util.getMetaContent(html, "name", "description")
        
    local author = html:match('Tác giả.-<a[^>]*>([^<]+)</a>') or html:match('Tác giả.-<div[^>]*>([^<]+)</div>')
    local status = html:match('Tình trạng.-<div[^>]*>([^<]+)</div>') or html:match('Tình trạng.-<a[^>]*>([^<]+)</a>')
    
    local genres = {}
    local genre_block = html:match('Thể loại.-<div class="summary%-content">(.-)</div>')
    if genre_block then
        for g_name in genre_block:gmatch('<a[^>]*>([^<]+)</a>') do
            table.insert(genres, Util.trim(g_name))
        end
    end

    return {
        description = Util.stripTags(description or ""),
        author = author and Util.trim(Util.stripTags(author)) or nil,
        status = status and Util.trim(Util.stripTags(status)) or nil,
        genres = genres,
    }
end

function Source:getStoryDetails(story)
    local html, err = Http:get(story.url, self:getCoverHeaders())
    if not html then return nil, err end
    return self:parseStoryDetails(html)
end

function Source:parseStoryPage(html, story, page)
    local chapters = {}
    
    -- Extract chapter links from "Chương đầu" and "Chương cuối"
    local first_chap_url = html:match('<a href="([^"]+)"[^>]*>Chương đầu</a>')
    local last_chap_url = html:match('<a href="([^"]+)"[^>]*>Chương cuối</a>')
    
    if first_chap_url and last_chap_url then
        local prefix, first_num = first_chap_url:match("([^/]+)-(%d+)/?$")
        local _, last_num = last_chap_url:match("([^/]+)-(%d+)/?$")
        
        first_num = tonumber(first_num)
        last_num = tonumber(last_num)
        
        if first_num and last_num and prefix then
            for i = first_num, last_num do
                local ch_url = story.url .. prefix .. "-" .. tostring(i) .. "/"
                table.insert(chapters, {
                    title = (prefix == "phan" and "Phần " or "Chương ") .. tostring(i),
                    url = Util.absoluteUrl(self.base_url, ch_url),
                    source_id = self.id,
                    story_url = story.url,
                    kind = self.kind,
                })
            end
        end
    end
    
    -- Fallback if no start/end button is found, try to extract directly from HTML
    if #chapters == 0 then
        for anchor_attrs, anchor_html in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
            local href = Util.getAttribute(anchor_attrs, "href")
            if href and (href:find("/chuong%-", 1, true) or href:find("/phan%-", 1, true)) and href:find(story.url, 1, true) then
                local title = Util.stripTags(anchor_html)
                table.insert(chapters, {
                    title = title ~= "" and title or Util.getAttribute(anchor_attrs, "title"),
                    url = Util.absoluteUrl(self.base_url, href),
                    source_id = self.id,
                    story_url = story.url,
                    kind = self.kind,
                })
            end
        end
        chapters = Util.uniqueBy(chapters, "url")
    end

    story.details = self:parseStoryDetails(html)
    return {
        story = story,
        chapters = chapters,
        page = 1,
        total_pages = 1,
    }
end

function Source:getStoryPage(story, page)
    if page and page > 1 then
        return { story = story, chapters = {}, page = page, total_pages = 1 }
    end
    local html, err = Http:get(story.url, self:getCoverHeaders())
    if not html then return nil, err end
    return self:parseStoryPage(html, story, page)
end

function Source:parseChapter(html, chapter)
    local chapter_title = html:match('<h1[^>]*class="[^"]*chapter%-title[^"]*"[^>]*>([%s%S]-)</h1>')
        or html:match('id="chapter%-heading"[^>]*>([%s%S]-)</h1>')
        
    local start_at = html:find('class="reading%-content"') or html:find('class="text%-left"')
    if not start_at then
        return nil, "Không tìm thấy nội dung chương"
    end
    start_at = html:find(">", start_at, true)

    local end_at = html:find('</div>%s*<div class="chap%-bottom"', start_at)
        or html:find('</div>%s*<div class="chapter%-content%-bottom"', start_at)
        or html:find('</article>', start_at)
    if not end_at then
        return nil, "Không xác định được điểm kết thúc chương"
    end

    local content = Util.sanitizeContentHtml(html:sub(start_at + 1, end_at - 1))

    return {
        title = chapter_title and Util.stripTags(chapter_title) or chapter.title,
        content = content,
        url = chapter.url,
        kind = self.kind,
    }
end

function Source:getChapter(chapter)
    local html, err = Http:get(chapter.url, self:getCoverHeaders())
    if not html then return nil, err end
    return self:parseChapter(html, chapter)
end

return Source
