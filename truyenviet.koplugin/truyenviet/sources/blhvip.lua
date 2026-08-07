local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local json = require("json")
local lfs = require("lfs")

local Source = {
    id = "blhvip",
    name = "Bàn Long VIP",
    kind = "text",
    base_url = "https://blhvip.vn",
}

local function getCookie()
    local path = lfs.currentdir() .. "/truyenviet_blhvip_cookie.txt"
    local f = io.open(path, "r")
    if not f then
        path = lfs.currentdir() .. "/settings/truyenviet_blhvip_cookie.txt"
        f = io.open(path, "r")
    end
    if f then
        local cookie = f:read("*all")
        f:close()
        return cookie:gsub("[\r\n]", "")
    end
    -- Fallback to the cookie provided by the user for VIP access
    return "XSRF-TOKEN=eyJpdiI6ImZWYmUrNmRqdW5nbEdqSFFwNkt5L1E9PSIsInZhbHVlIjoiNmZGN21FNmZzc0ZuWndKZTNxMWdaeStPZ0VPalM1bEN6STU2M0NoazVBc041TlVNRng1Y1ZwYUpSUFJ6bkgyRHJRbGhRUHJIYUdxaktzZUZsZkJVSXN6cVJsSlNEZ2RkQ1RIWVNFaUlpL3Z4dS9ZYTd2dVhNMFQvT3FxdElUZXMiLCJtYWMiOiIzYjc1NzAyOTVhZjViMDZhNzVjNDA3Mzg3ODg3ODU1YmIyYzI1ZjM0MzY2ODFhOWNkOTkxMzhjNjYwZjFjOTUzIiwidGFnIjoiIn0%3D"
end

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
    local url = "https://api.blhvip.vn/v1/search?q=" .. Util.urlEncode(keyword)
    local headers = {}
    local cookie = getCookie()
    if cookie and cookie ~= "" then headers["Cookie"] = cookie end
    local content, err = Http:get(url, headers)
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
    local headers = {}
    local cookie = getCookie()
    if cookie and cookie ~= "" then headers["Cookie"] = cookie end
    local content, err = Http:get(url, headers)
    if not content then return nil, err end
    
    local stories = self:parseList(content)
    local total_pages = page
    if content:find('href="[^"]+%?page=' .. (page + 1) .. '"') then
        total_pages = page + 1
    end
    
    return {
        stories = stories,
        page = page,
        total_pages = total_pages,
        genres = self:getGenresList() or {}
    }
end

function Source:getGenresList()
    return {
        { name = "Truyện Hot", slug = "truyen-hot", url = "/truyen-hot" },
        { name = "Truyện Mới Nhất", slug = "truyen-moi-nhat", url = "/truyen-moi-nhat" },
        { name = "Truyện Hoàn Thành", slug = "truyen-hoan-thanh", url = "/truyen-hoan-thanh" },
        { name = "Yêu Thích Tháng", slug = "truyen-yeu-thich", url = "/truyen-yeu-thich" },
        { name = "Thịnh Hành Tuần", slug = "truyen-thinh-hanh-trong-tuan", url = "/truyen-thinh-hanh-trong-tuan" },
    }
end

function Source:getCompleted(page)
    local res = self:_getList("/truyen-hoan-thanh", page or 1)
    res.title = "Truyện Hoàn Thành"
    return res
end

function Source:getGenre(genre, page)
    local url_path = type(genre) == "table" and genre.url or ("/" .. genre)
    local res = self:_getList(url_path, page or 1)
    res.title = type(genre) == "table" and genre.name or "Danh sách"
    return res
end

function Source:getStoryDetails(story)
    local headers = {}
    local cookie = getCookie()
    if cookie and cookie ~= "" then headers["Cookie"] = cookie end
    local content, err = Http:get(story.url, headers)
    if not content then return nil, err end

    local author = content:match('<a[^>]+href="/tac%-gia/[^"]*"[^>]*>([^<]*)</a>')
    if author then 
        author = Util.stripTags(author):gsub("\n", "") 
    end

    local description = content:match('<div class="box%-story%-content[^"]*"[^>]*>(.-)</div>')
    if description then 
        description = Util.stripTags(description) 
    end

    local status = content:match('Đã hoàn thành') and "Hoàn thành" or "Đang ra"
    
    return {
        author = author or "Khuyết Danh",
        description = description or "",
        status = status,
        genres = {},
    }
end

function Source:getStoryPage(story, page)
    page = page or 1
    local story_slug = story.url:match("/truyen/([^/?]+)")
    if not story_slug then return nil, "Invalid story URL" end
    
    local api_url = "https://api.blhvip.vn/v1/story/" .. story_slug .. "/chapter_list?page=" .. page .. "&new=0"
    local headers = {}
    local cookie = getCookie()
    if cookie and cookie ~= "" then headers["Cookie"] = cookie end
    local content, err = Http:get(api_url, headers)
    if not content then return nil, err end
    
    local ok, parsed = pcall(json.decode, content)
    if not ok or type(parsed) ~= "table" or not parsed.data then 
        return nil, "Lỗi giải mã JSON"
    end
    
    local chapters = {}
    for i, item in ipairs(parsed.data) do
        if item.name and item.url then
            local order = (page - 1) * 100 + i
            table.insert(chapters, {
                title = item.name,
                url = self.base_url .. item.url,
                order = order,
                slug = story_slug,
                kind = "text",
                source_id = self.id,
                story_url = story.url,
            })
        end
    end
    
    local total_pages = parsed.total_page or 1
    
    if page == 1 then
        story.details = self:getStoryDetails(story)
    end
    
    return {
        story = story,
        chapters = chapters,
        page = page,
        total_pages = total_pages,
    }
end

function Source:getChapter(chapter)
    local headers = {}
    local cookie = getCookie()
    if cookie and cookie ~= "" then headers["Cookie"] = cookie end
    local content, err = Http:get(chapter.url, headers)
    if not content then return nil, err end
    
    if content:find('class="[^"]*content%-lock[^"]*"') then
        return nil, "Chương VIP bị khóa! Bạn cần Đăng nhập và mua Linh Thạch trên blhvip.vn.\n\n(Nếu đã có tài khoản, hãy copy nội dung Cookie và dán vào file truyenviet_blhvip_cookie.txt trong thư mục gốc của KOReader để đọc nhé!)"
    end
    
    local chapter_content = content:match('<div[^>]+class="[^"]*s%-content[^"]*"[^>]*>(.*)<div class="container chapter%-page%-apply"')
    if not chapter_content then
        chapter_content = content:match('<div id="chapter%-content"[^>]*>(.-)</div>')
    end
    
    if not chapter_content then
        return nil, "Không lấy được nội dung chương"
    end
    
    -- Filter out scripts and ads
    chapter_content = chapter_content:gsub("<script.-</script>", "")
    chapter_content = chapter_content:gsub("<style.-</style>", "")
    chapter_content = chapter_content:gsub("<iframe.-</iframe>", "")
    chapter_content = chapter_content:gsub('<div[^>]+class="ads".-</div>', "")
    
    local title = content:match('<h1[^>]*>([^<]+)</h1>')
    return {
        title = title and Util.stripTags(title) or chapter.title,
        content = "<div>" .. chapter_content .. "</div>",
        url = chapter.url,
        kind = "text",
    }
end

function Source:getHot(page)
    local res = self:_getList("/truyen-hot", page or 1)
    res.title = "Truyện Hot"
    return res
end

function Source:getLatest(page)
    local res = self:_getList("/truyen-moi-nhat", page or 1)
    res.title = "Truyện Mới Nhất"
    return res
end

return Source
