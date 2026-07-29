local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local ko_util = require("util")

local Source = {
    id = "akaytruyen",
    name = "AkayTruyen",
    kind = "text",
    base_url = "https://akaytruyen.com",
    reversed_chapters = true,
    supports_login = true,
    _cookies = nil,
    _logged_in = false,
    _home_cache = nil,
    _home_cache_time = 0,
}

local function parseCookies(headers)
    local cookies = {}
    if not headers then return cookies end
    local raw = headers["set-cookie"] or headers["Set-Cookie"]
    if type(raw) == "string" then
        for name, value in raw:gmatch("([%w_%-]+)=([^;,]+)") do
            local lower_name = name:lower()
            if lower_name ~= "expires" and lower_name ~= "path" and lower_name ~= "max-age" and lower_name ~= "domain" and lower_name ~= "samesite" then
                cookies[name] = value
            end
        end
    elseif type(raw) == "table" then
        for _, cookie_string in ipairs(raw) do
            local name, value = cookie_string:match("^%s*([^=]+)=([^;]*)")
            if name then cookies[name] = value end
        end
    end
    return cookies
end

local function mergeCookies(existing, incoming)
    existing = existing or {}
    for name, value in pairs(incoming or {}) do
        existing[name] = value
    end
    return existing
end

local function cookieHeader(cookies)
    local parts = {}
    for name, value in pairs(cookies or {}) do
        table.insert(parts, name .. "=" .. value)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, "; ") or nil
end

local function isVipLocked(html)
    return html and (html:match('<div[^>]-class=["\'][^"\']*access%-denied%-container') or html:find("Chương này dành cho tài khoản VIP", 1, true))
end

local function vipError()
    return "Chương VIP bị khóa. Hãy đăng nhập tài khoản AkayTruyen trong Quản lý nguồn."
end

function Source:getCoverHeaders()
    local headers = {
        ["Referer"] = self.base_url .. "/",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ["Connection"] = "keep-alive",
    }
    local cookie = cookieHeader(self._cookies)
    if cookie then headers["Cookie"] = cookie end
    return headers
end

function Source:getPageHeaders()
    return self:getCoverHeaders()
end

function Source:updateCookies(headers)
    self._cookies = mergeCookies(self._cookies, parseCookies(headers))
end

function Source:authGet(url)
    local content, err, headers, code = Http:get(url, self:getPageHeaders())
    self:updateCookies(headers)
    return content, err, headers, code
end

function Source:authPost(url, body, headers, options)
    local request_headers = self:getPageHeaders()
    for name, value in pairs(headers or {}) do
        request_headers[name] = value
    end
    local content, err, response_headers, code = Http:request("POST", url, body, request_headers, options)
    self:updateCookies(response_headers)
    return content, err, response_headers, code
end

function Source:login(username, password)
    if not username or username == "" or not password or password == "" then
        return nil, "Email và mật khẩu không được để trống"
    end

    self._cookies = nil
    self._logged_in = false
    local login_html, login_err = self:authGet(self.base_url .. "/login")
    if not login_html then
        return nil, "Không thể tải trang đăng nhập: " .. tostring(login_err)
    end

    local csrf_token = login_html:match('name="_token"%s+value="([^"]+)"')
        or login_html:match('name="_token"%s+value=\'([^\']+)\'')
        or login_html:match('name="csrf%-token"%s+content="([^"]+)"')
    if not csrf_token then
        return nil, "Không tìm thấy mã bảo vệ đăng nhập AkayTruyen"
    end

    local body = table.concat({
        "_token=" .. ko_util.urlEncode(csrf_token),
        "email=" .. ko_util.urlEncode(username),
        "password=" .. ko_util.urlEncode(password),
        "remember=1",
    }, "&")
    local _, post_err, response_headers, code = self:authPost(
        self.base_url .. "/login",
        body,
        {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Referer"] = self.base_url .. "/login",
        },
        { redirect = false }
    )

    local location = response_headers and (response_headers.location or response_headers.Location) or ""
    if not code or code < 300 or code >= 400 or location:find("/login", 1, true) then
        return nil, "Đăng nhập AkayTruyen thất bại: " .. tostring(post_err or "sai email/mật khẩu")
    end

    local account_html, account_err = self:authGet(self.base_url .. "/")
    if not account_html then
        return nil, "Không thể xác minh phiên đăng nhập: " .. tostring(account_err)
    end

    self._logged_in = true
    return true
end

function Source:ensureLoggedIn()
    if self._logged_in and cookieHeader(self._cookies) then return true end
    local CredentialManager = require("truyenviet/credential_manager")
    local credential = CredentialManager:getCredential(self.id)
    if not credential then return nil, "Chưa lưu tài khoản AkayTruyen" end
    return self:login(credential.username, credential.password)
end

function Source:isLoggedIn()
    return self._logged_in == true
end

-- Tự động bóc tách truyện cực nhanh từ HTML (Tối ưu hóa tránh treo UI)
function Source:parseSearch(html)
    if not html or #html < 100 then return {} end
    local stories = {}
    local seen = {}

    -- Quét nhanh theo mẫu đường dẫn /truyen/
    for href, title_html in html:gmatch('href=["\'](https?://akaytruyen%.com/truyen/[^"\'%?#]+)["\'][^>]*>([%s%S]-)</a>') do
        if not seen[href] then
            local title = Util.trim(Util.stripTags(title_html)):gsub("%s+", " ")
            if #title > 1 and not title:find("^Truyện") and not title:find("^Thể loại") then
                seen[href] = true
                -- Tìm ảnh bìa trong cùng khối HTML
                local img_src = title_html:match('src="([^"]+)"') or title_html:match('data%-src="([^"]+)"')
                table.insert(stories, {
                    source_id = self.id,
                    title = Util.decodeHtml(title),
                    url = href,
                    cover_url = img_src and Util.absoluteUrl(self.base_url, img_src) or nil,
                    kind = self.kind,
                })
            end
        end
    end

    -- Fallback quét href tương đối /truyen/
    if #stories == 0 then
        for rel_href in html:gmatch('href=["\'](/truyen/[^"\'%?#]+)["\']') do
            local full_url = Util.absoluteUrl(self.base_url, rel_href)
            if not seen[full_url] then
                seen[full_url] = true
                local slug = rel_href:match("([^/]+)$") or "truyen"
                local clean_title = slug:gsub("%-", " "):gsub("^%l", string.upper)
                table.insert(stories, {
                    source_id = self.id,
                    title = clean_title,
                    url = full_url,
                    cover_url = nil,
                    kind = self.kind,
                })
            end
        end
    end

    return stories
end

function Source:search(query)
    if not query or query == "" then
        return self:getCompleted(1)
    end
    local encoded = ko_util.urlEncode(query):gsub("%%20", "+")
    local url = self.base_url .. "/tim-kiem?keyword=" .. encoded
    local html, err = self:authGet(url)
    if not html then return nil, err end
    local stories = self:parseSearch(html)
    return stories
end

function Source:parseListing(html, page)
    return {
        stories = self:parseSearch(html),
        genres = Util.parseGenres(html, self.base_url),
        page = page or 1,
        total_pages = Util.maxPage(html, page),
    }
end

-- Bộ nhớ đệm Trang Chủ (Cache 900KB HTML 120s tránh tải đi tải lại làm treo KOReader)
function Source:getHomePage()
    local now = os.time()
    if self._home_cache and (now - self._home_cache_time) < 120 then
        return self._home_cache
    end

    local html, err = self:authGet(self.base_url .. "/")
    if html then
        self._home_cache = html
        self._home_cache_time = now
    end
    return html, err
end

local function extractHomeSection(html, start_marker, end_marker)
    if not html then return "" end
    local start_at = html:find(start_marker, 1, true)
    if not start_at then return html end
    local end_at = end_marker and html:find(end_marker, start_at + #start_marker, true)
    return html:sub(start_at, (end_at and end_at - 1) or #html)
end

function Source:parseHomeSection(html, page, start_marker, end_marker, title)
    local section_html = extractHomeSection(html, start_marker, end_marker)
    return {
        stories = self:parseSearch(section_html),
        genres = Util.parseGenres(html, self.base_url),
        page = page or 1,
        total_pages = 1,
        title = title,
    }
end

function Source:getCompleted(page)
    page = page or 1
    local html, err = self:getHomePage()
    if not html then return nil, err end
    return self:parseHomeSection(html, page, 'section-stories-full', 'id_feedback_button', "Truyện hoàn thành")
end

function Source:getHot(page)
    page = page or 1
    local html, err = self:getHomePage()
    if not html then return nil, err end
    return self:parseHomeSection(html, page, 'section-stories-hot', 'section-stories-new', "Truyện hot")
end

function Source:getUpdating(page)
    page = page or 1
    local html, err = self:getHomePage()
    if not html then return nil, err end
    return self:parseHomeSection(html, page, 'section-stories-new', 'section-stories-full', "Truyện mới cập nhật")
end

function Source:getGenre(genre, page)
    page = page or 1
    local url = Util.withTrailingSlash(genre.url)
    if page > 1 then url = url .. "?page=" .. page end
    local html, err = self:authGet(url)
    if not html then return nil, err end
    local result = self:parseListing(html, page)
    result.title = genre.name
    result.genre = genre
    return result
end

function Source:parseStoryDetails(html)
    if not html then return { description = "", author = "Tác Giả", status = "Đang cập nhật", genres = {} } end
    local description_html = html:match('<div[^>]-class="[^"]*desc[^"]*"[^>]-itemprop="description"[^>]*>([%s%S]-)</div>')
        or html:match('<div[^>]-class="[^"]*desc[^"]*"[^>]*>([%s%S]-)</div>')
        or html:match('<div[^>]-itemprop="description"[^>]*>([%s%S]-)</div>')

    local author = html:match('itemprop="author"[^>]*>([%s%S]-)</a>')
        or html:match('class="author[^"]*"[^>]*>([%s%S]-)</a>')

    return {
        description = description_html and Util.stripTags(description_html) or Util.getMetaContent(html, "name", "description"),
        author = author and Util.stripTags(author) or "Tác Giả",
        status = "Đang cập nhật",
        genres = Util.parseGenreNames(html),
    }
end

function Source:getStoryDetails(story)
    local html, err = self:authGet(story.url)
    if not html then return nil, err end
    return self:parseStoryDetails(html)
end

function Source:parseStoryPage(html, story, page)
    if not html then return { story = story, chapters = {}, page = page or 1, total_pages = 1 } end

    local chapters = {}
    local seen = {}
    local story_url_clean = story.url:gsub("%?.*$", ""):gsub("/$", "")
    local story_slug = story_url_clean:match("([^/]+)$") or ""

    -- Quét nhanh các liên kết chương
    for href, anchor_html in html:gmatch('<a[^>]+href=["\']([^"\'%?#]+)["\'][^>]*>([%s%S]-)</a>') do
        if href:find(story_slug, 1, true) and (href:find("/chuong-") or href:find("/chapter-") or href:find("/c-") or href:match("/%d+$")) then
            local abs_href = Util.absoluteUrl(self.base_url, href)
            if not seen[abs_href] then
                seen[abs_href] = true
                local title = Util.decodeHtml(Util.trim(Util.stripTags(anchor_html):gsub("%s+", " ")))
                if title == "" then title = "Chương " .. (#chapters + 1) end
                table.insert(chapters, {
                    title = title,
                    url = abs_href,
                    source_id = self.id,
                    story_url = story.url,
                    kind = self.kind,
                })
            end
        end
    end

    local total_pages = tonumber(html:match('class="jump%-input[^"]*"[^>]-max="(%d+)"')) or 1
    if total_pages == 1 then
        for p in html:gmatch('page=(%d+)') do
            total_pages = math.max(total_pages, tonumber(p) or 1)
        end
    end

    story.details = self:parseStoryDetails(html)
    return {
        story = story,
        chapters = chapters,
        page = page or 1,
        total_pages = total_pages,
    }
end

function Source:getStoryPage(story, page)
    page = page or 1
    local story_url = story.url:gsub("%?.*$", "")
    local page_url = page == 1 and story_url or (story_url .. "?page=" .. page)

    local html, err = self:authGet(page_url)
    if not html then return nil, err end

    return self:parseStoryPage(html, story, page)
end

function Source:getAllChapters(story, progress_cb)
    local story_url = story.url:gsub("%?.*$", "")
    local first_html, err = self:authGet(story_url)
    if not first_html then return nil, err end

    local total_pages = tonumber(first_html:match('class="jump%-input[^"]*"[^>]-max="(%d+)"')) or 1
    if total_pages == 1 then
        for p in first_html:gmatch('page=(%d+)') do
            total_pages = math.max(total_pages, tonumber(p) or 1)
        end
    end

    -- Giới hạn tối đa 30 trang để tránh làm treo KOReader khi bộ truyện quá dài
    total_pages = math.min(total_pages, 30)

    local all_chapters = {}
    local seen_chapter_urls = {}
    for p = 1, total_pages do
        if progress_cb then
            progress_cb(string.format("Lấy danh sách chương trang %d/%d...", p, total_pages))
        end
        local p_url = p == 1 and story_url or (story_url .. "?page=" .. p)
        local html
        if p == 1 then
            html = first_html
        else
            html = self:authGet(p_url)
        end

        if html then
            local page_res = self:parseStoryPage(html, story, p)
            for _, ch in ipairs(page_res.chapters) do
                if not seen_chapter_urls[ch.url] then
                    seen_chapter_urls[ch.url] = true
                    table.insert(all_chapters, ch)
                end
            end
        end
    end

    return all_chapters
end

function Source:parseChapter(html, chapter)
    if isVipLocked(html) then return nil, vipError() end
    if not html or #html < 50 then return nil, "Không nhận được nội dung từ AkayTruyen" end

    local chapter_title = html:match("<h[12][^>]*>([%s%S]-)</h[12]>")

    local content = html:match('<div[^>]-id="chapter%-content"[^>]*>([%s%S]-)</div>')
        or html:match('<div[^>]-class="[^"]*chapter%-content[^"]*"[^>]*>([%s%S]-)</div>')
        or html:match('<div[^>]-id="chapter%-c"[^>]*>([%s%S]-)</div>')
        or html:match('<div[^>]-class="[^"]*content%-chap[^"]*"[^>]*>([%s%S]-)</div>')

    if not content then return nil, "Không tìm thấy nội dung chương" end

    content = Util.sanitizeContentHtml(content)

    return {
        title = chapter_title and Util.stripTags(chapter_title) or chapter.title,
        content = content,
        url = chapter.url,
        kind = self.kind,
    }
end

function Source:getChapter(chapter)
    local html, err = self:authGet(chapter.url)
    if not html then return nil, err end
    if isVipLocked(html) and not self:isLoggedIn() then
        local CredentialManager = require("truyenviet/credential_manager")
        if CredentialManager:hasCredential(self.id) then
            local logged_in, login_err = self:ensureLoggedIn()
            if logged_in then
                html, err = self:authGet(chapter.url)
                if not html then return nil, err end
            else
                return nil, vipError() .. "\nĐăng nhập thất bại: " .. tostring(login_err)
            end
        end
    end
    return self:parseChapter(html, chapter)
end

return Source
