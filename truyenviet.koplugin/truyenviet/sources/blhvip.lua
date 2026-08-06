local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local json = require("json")
local Debug = require("truyenviet/debugger")

local Source = {
    id = "blhvip",
    name = "Bàn Long VIP",
    kind = "text",
    base_url = "https://blhvip.vn",
}

function Source:parseSearch(html)
    local ok, parsed = pcall(json.decode, html)
    if not ok or not parsed or type(parsed) ~= "table" then
        return {}
    end
    
    local stories = {}
    if parsed.data then
        for _, item in ipairs(parsed.data) do
            table.insert(stories, {
                source_id = self.id,
                title = item.name,
                url = self.base_url .. "/truyen/" .. item.slug,
                cover_url = item.img_url,
                kind = self.kind,
            })
        end
    end
    return stories
end

function Source:search(keyword, page)
    -- page is mostly 1 for search because it's a simple search API
    local url = "https://api.blhvip.vn/v1/search?q=" .. Util.urlEncode(keyword)
    local content, err = Http:get(url)
    if not content then return nil, err end
    
    local stories = self:parseSearch(content)
    return stories, 1, 1
end

function Source:parseList(html)
    local stories = {}
    for attrs, title in html:gmatch('<a([^>]+href="truyen/[^"]+"[^>]*)>([^<]*)</a>') do
        if attrs:find('class="title') then
            local href = attrs:match('href="([^"]+)"')
            local clean_title = attrs:match('title="([^"]+)"') or Util.stripTags(title)
            table.insert(stories, {
                source_id = self.id,
                title = clean_title,
                url = Util.absoluteUrl(self.base_url, "/" .. href),
                kind = self.kind,
            })
        end
    end
    return Util.uniqueBy(stories, "url")
end

function Source:_getList(path, page)
    local url = self.base_url .. path
    if page and page > 1 then
        url = url .. "?page=" .. page
    end
    local content, err = Http:get(url)
    if not content then return nil, err end
    
    local stories = self:parseList(content)
    local next_page = nil
    if content:find('href="[^"]+%?page=' .. (page + 1) .. '"') then
        next_page = page + 1
    else
        next_page = page
    end
    return stories, page, next_page
end

function Source:getHot(page)
    return self:_getList("/truyen-hot", page)
end

function Source:getLatest(page)
    return self:_getList("/truyen-moi-nhat", page)
end

function Source:getCompleted(page)
    return self:_getList("/truyen-hoan-thanh", page)
end

function Source:getFavorites(page)
    return self:_getList("/truyen-yeu-thich", page)
end

function Source:getTrending(page)
    return self:_getList("/truyen-thinh-hanh-trong-tuan", page)
end

function Source:getGenres()
    return {
        { name = "Truyện Hot", getList = function(p) return self:getHot(p) end },
        { name = "Truyện Mới Nhất", getList = function(p) return self:getLatest(p) end },
        { name = "Truyện Hoàn Thành", getList = function(p) return self:getCompleted(p) end },
        { name = "Yêu Thích Tháng", getList = function(p) return self:getFavorites(p) end },
        { name = "Thịnh Hành Tuần", getList = function(p) return self:getTrending(p) end },
    }
end

function Source:getDetails(url)
    local content, err = Http:get(url)
    if not content then return nil, err end

    local title = content:match('<h1[^>]*>([^<]*)</h1>')
    if title then 
        title = Util.stripTags(title):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "") 
    end
    
    local author = content:match('<a[^>]+href="/tac%-gia/[^"]*"[^>]*>([^<]*)</a>')
    if author then 
        author = Util.stripTags(author):gsub("\n", "") 
    end

    local description = content:match('<div class="box%-story%-content[^"]*"[^>]*>(.-)</div>')
    if description then 
        description = Util.stripTags(description) 
    end

    local cover_url = content:match('<img[^>]+src="([^"]+)"[^>]+alt="' .. (title or "") .. '"')
    if not cover_url then
        cover_url = content:match('<div class="img%-story[^>]*>%s*<img[^>]+src="([^"]+)"')
    end
    if cover_url then cover_url = Util.absoluteUrl(self.base_url, cover_url) end

    return {
        source_id = self.id,
        url = url,
        title = title or "Unknown",
        author = author or "Unknown",
        description = description or "",
        cover_url = cover_url,
        kind = self.kind,
        status = content:match('Đã hoàn thành') and "Completed" or "Ongoing",
    }
end

function Source:getChapters(url)
    local story_slug = url:match("/truyen/([^/]+)")
    if not story_slug then return nil, "Invalid story URL" end
    
    local page = 1
    local chapters = {}
    
    while true do
        local api_url = "https://api.blhvip.vn/v1/story/" .. story_slug .. "/chapter_list?page=" .. page .. "&new=0"
        local content, err = Http:get(api_url)
        if not content then break end
        
        local ok, parsed = pcall(json.decode, content)
        if not ok or type(parsed) ~= "table" or not parsed.data or #parsed.data == 0 then 
            break 
        end
        
        for _, item in ipairs(parsed.data) do
            if item.name and item.url then
                table.insert(chapters, {
                    title = item.name,
                    url = self.base_url .. item.url,
                })
            end
        end
        
        local total_page = parsed.total_page or 1
        if page >= total_page then break end
        page = page + 1
    end
    
    return chapters
end

function Source:getChapterContent(url)
    local content, err = Http:get(url)
    if not content then return nil, err end
    
    local chapter_content = content:match('<div id="chapter%-content"[^>]*>(.-)</div>%s*<div')
    if not chapter_content then
        chapter_content = content:match('<div id="chapter%-content"[^>]*>(.-)</div>')
    end
    
    if not chapter_content then
        return nil, "Không lấy được nội dung chương"
    end
    
    local title = content:match('<h1[^>]*>([^<]+)</h1>')
    return {
        title = title and Util.stripTags(title) or "Chương",
        html = chapter_content
    }
end

return Source
