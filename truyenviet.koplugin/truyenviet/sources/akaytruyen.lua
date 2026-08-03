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
    -- Akay chapter pages are large. Keep rolling prefetch cooperative and
    -- strictly serial so it cannot saturate the single-threaded reader UI.
    max_concurrent = 1,
    _cookies = nil,
    _logged_in = false,
    _home_data = nil,
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

function Source:authGetAsync(url)
    local content, err, headers, code = Http:requestAsync(
        "GET",
        url,
        nil,
        self:getPageHeaders()
    )
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

local function canonicalStoryUrl(base_url, href)
    if not href or not href:find("/truyen/", 1, true) then return nil end
    local full_url = Util.absoluteUrl(base_url, href)
    if not full_url then return nil end
    return full_url:gsub("#.*$", ""):gsub("%?.*$", ""):gsub("/+$", "")
end

local function cleanStoryTitle(raw)
    local title = Util.trim(Util.stripTags(raw or "")):gsub("%s+", " ")
    title = title:gsub("%s+Full%s*$", "")
        :gsub("%s+Hot%s*$", "")
        :gsub("%s+New%s*$", "")
        :gsub("%s+Đang viết%s*$", "")
    return Util.trim(title)
end

-- Akay uses separate anchors for image and title in several listings. Merge
-- all information for the same canonical URL before emitting a story.
local function parseStoryAnchors(source, html)
    local entries = {}
    local ordered_urls = {}

    for attrs, body in tostring(html or ""):gmatch("<a([^>]*)>([%s%S]-)</a>") do
        local url = canonicalStoryUrl(
            source.base_url,
            Util.getAttribute(attrs, "href")
        )
        if url then
            local entry = entries[url]
            if not entry then
                entry = {
                    source_id = source.id,
                    url = url,
                    kind = source.kind,
                    _title_rank = 0,
                }
                entries[url] = entry
                ordered_urls[#ordered_urls + 1] = url
            end

            local cover = body:match('data%-src%s*=%s*"([^"]+)"')
                or body:match("data%-src%s*=%s*'([^']+)'")
                or body:match('src%s*=%s*"([^"]+)"')
                or body:match("src%s*=%s*'([^']+)'")
            if cover and not entry.cover_url then
                entry.cover_url = Util.absoluteUrl(source.base_url, cover)
            end

            local class_attr = Util.getAttribute(attrs, "class") or ""
            local attribute_title = Util.getAttribute(attrs, "title")
            local image_alt = body:match('<img[^>]-alt%s*=%s*"([^"]+)"')
                or body:match("<img[^>]-alt%s*=%s*'([^']+)'")
            local title
            local title_rank = 0

            if class_attr:find("story-name", 1, true)
                    or class_attr:find("story-title", 1, true)
                    or class_attr:find("title-text-story", 1, true) then
                title = cleanStoryTitle(body)
                title_rank = 4
            elseif attribute_title and attribute_title ~= "" then
                title = cleanStoryTitle(attribute_title)
                title_rank = 3
            elseif image_alt and image_alt ~= "" then
                title = cleanStoryTitle(image_alt)
                title_rank = 2
            else
                title = cleanStoryTitle(body)
                title_rank = 1
            end

            if title ~= ""
                    and title_rank >= entry._title_rank
                    and not title:find("^Thể loại") then
                entry.title = Util.decodeHtml(title)
                entry._title_rank = title_rank
            end
        end
    end

    local stories = {}
    for _, url in ipairs(ordered_urls) do
        local entry = entries[url]
        if entry.title and entry.title ~= "" then
            entry._title_rank = nil
            stories[#stories + 1] = entry
        end
    end
    return stories
end

function Source:parseSearch(html)
    return parseStoryAnchors(self, html)
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

local function extractHomeSection(html, start_marker, end_marker)
    if not html then return "" end
    local start_at = html:find(start_marker, 1, true)
    if not start_at then return "" end
    local end_at = end_marker and html:find(end_marker, start_at + #start_marker, true)
    return html:sub(start_at, (end_at and end_at - 1) or #html)
end

function Source:parseHomeSection(html, page, start_marker, end_marker, title)
    local section_html = extractHomeSection(html, start_marker, end_marker)
    if section_html == "" then
        return nil, "Không tìm thấy mục '" .. title .. "' trên AkayTruyen"
    end
    return {
        stories = self:parseSearch(section_html),
        genres = Util.parseGenres(html, self.base_url),
        page = page or 1,
        total_pages = 1,
        title = title,
    }
end

local function copyItems(items)
    local result = {}
    for index, item in ipairs(items or {}) do
        local copied = {}
        for key, value in pairs(item) do copied[key] = value end
        result[index] = copied
    end
    return result
end

function Source:parseHomeData(html)
    local hot_html = extractHomeSection(
        html,
        '<div class="section-stories-hot',
        '<div class="section-stories-new'
    )
    local updating_html = extractHomeSection(
        html,
        '<div class="section-stories-new',
        '<div class="section-stories-full'
    )
    local completed_html = extractHomeSection(
        html,
        '<div class="section-stories-full',
        '<div id="id_feedback_button"'
    )
    if hot_html == "" or updating_html == "" or completed_html == "" then
        return nil, "Trang chủ AkayTruyen đã đổi cấu trúc danh sách"
    end

    local hot = parseStoryAnchors(self, hot_html)
    local updating = parseStoryAnchors(self, updating_html)
    local completed = parseStoryAnchors(self, completed_html)
    local cover_by_url = {}
    for _, group in ipairs({ hot, completed }) do
        for _, story in ipairs(group) do
            if story.cover_url then cover_by_url[story.url] = story.cover_url end
        end
    end
    for _, story in ipairs(updating) do
        story.cover_url = story.cover_url or cover_by_url[story.url]
    end

    return {
        hot = hot,
        updating = updating,
        completed = completed,
        genres = Util.parseGenres(html, self.base_url),
    }
end

-- Cache parsed results, not the roughly 900 KB homepage HTML.
function Source:getHomeData()
    local now = os.time()
    if self._home_data and (now - self._home_cache_time) < 120 then
        return self._home_data
    end

    local html, err = self:authGet(self.base_url .. "/")
    if not html then return nil, err end
    local data, parse_err = self:parseHomeData(html)
    if not data then return nil, parse_err end
    self._home_data = data
    self._home_cache_time = now
    return data
end

function Source:getHomePage()
    return self:authGet(self.base_url .. "/")
end

local function homeListing(data, key, page, title)
    return {
        stories = copyItems(data[key]),
        genres = copyItems(data.genres),
        page = page or 1,
        total_pages = 1,
        title = title,
    }
end

function Source:getCompleted(page)
    page = page or 1
    local data, err = self:getHomeData()
    if not data then return nil, err end
    return homeListing(data, "completed", page, "Truyện hoàn thành")
end

function Source:getHot(page)
    page = page or 1
    local data, err = self:getHomeData()
    if not data then return nil, err end
    return homeListing(data, "hot", page, "Truyện hot")
end

function Source:getUpdating(page)
    page = page or 1
    local data, err = self:getHomeData()
    if not data then return nil, err end
    return homeListing(data, "updating", page, "Truyện mới cập nhật")
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

local function chapterPageCount(html)
    local total_pages = 1
    for input_tag in tostring(html or ""):gmatch("<input[^>]*>") do
        local class_attr = Util.getAttribute(input_tag, "class") or ""
        if class_attr:find("jump-input", 1, true) then
            total_pages = math.max(
                total_pages,
                tonumber(Util.getAttribute(input_tag, "max")) or 1
            )
        end
    end
    if total_pages == 1 then
        for value in tostring(html or ""):gmatch("page=(%d+)") do
            total_pages = math.max(total_pages, tonumber(value) or 1)
        end
    end
    return total_pages
end

function Source:parseStoryPage(html, story, page, include_details)
    if not html then
        return {
            story = story,
            chapters = {},
            page = page or 1,
            total_pages = 1,
        }
    end

    local chapters = {}
    local seen = {}
    local story_url_clean = story.url:gsub("#.*$", "")
        :gsub("%?.*$", "")
        :gsub("/+$", "")
    local story_slug = story_url_clean:match("([^/]+)$") or ""
    local chapter_prefix = self.base_url:gsub("/+$", "")
        .. "/"
        .. story_slug
        .. "/"

    for attrs, body in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
        local href = Util.getAttribute(attrs, "href")
        if href then
            local chapter_url = Util.absoluteUrl(self.base_url, href)
            chapter_url = chapter_url
                and chapter_url:gsub("#.*$", ""):gsub("%?.*$", ""):gsub("/+$", "")
            local class_attr = Util.getAttribute(attrs, "class") or ""
            local normalized_class = " " .. class_attr:gsub("%s+", " ") .. " "
            local is_chapter_anchor = normalized_class:find(
                " chapter-link-mobile ",
                1,
                true
            ) ~= nil
                or body:find("chapter-number", 1, true) ~= nil
                or body:find("chapter-title", 1, true) ~= nil
            local has_prefix = chapter_url
                and chapter_url:sub(1, #chapter_prefix) == chapter_prefix
            local tail = has_prefix
                and chapter_url:sub(#chapter_prefix + 1)
                or ""
            local is_single_segment = tail ~= ""
                and not tail:find("/", 1, true)

            if is_chapter_anchor
                    and is_single_segment
                    and not seen[chapter_url] then
                seen[chapter_url] = true
                local number_html = body:match(
                    '<div[^>]-class="[^"]*chapter%-number[^"]*"[^>]*>'
                        .. "([%s%S]-)</div>"
                )
                local title_html = body:match(
                    '<div[^>]-class="[^"]*chapter%-title[^"]*"[^>]*>'
                        .. "([%s%S]-)</div>"
                )
                local number = cleanStoryTitle(number_html)
                local title_part = cleanStoryTitle(title_html)
                local title
                if number ~= "" and title_part ~= "" then
                    title = number .. ": " .. title_part
                elseif number ~= "" then
                    title = number
                elseif title_part ~= "" then
                    title = title_part
                else
                    title = cleanStoryTitle(body)
                end
                if title == "" then
                    title = Util.getAttribute(attrs, "title") or "Chương"
                end

                chapters[#chapters + 1] = {
                    title = Util.decodeHtml(title),
                    url = chapter_url,
                    source_id = self.id,
                    story_url = story.url,
                    kind = self.kind,
                }
            end
        end
    end

    if include_details then story.details = self:parseStoryDetails(html) end
    return {
        story = story,
        chapters = chapters,
        page = page or 1,
        total_pages = chapterPageCount(html),
    }
end

local function chapterEndpoint(story, page)
    local story_url = story.url:gsub("#.*$", "")
        :gsub("%?.*$", "")
        :gsub("/+$", "")
    return story_url .. "/search-chapters?search=&page=" .. tostring(page or 1)
end

local function decodeChapterFragment(raw)
    local payload = Util.parseJson(raw)
    if type(payload) == "table" and type(payload.html) == "string" then
        return payload.html
    end
    return nil, "Phản hồi danh sách chương AkayTruyen không hợp lệ"
end

function Source:getChapterListHtml(story, page)
    page = page or 1
    local raw, endpoint_err = self:authGet(chapterEndpoint(story, page))
    if raw then
        local fragment, decode_err = decodeChapterFragment(raw)
        if fragment then return fragment, nil, false end
        endpoint_err = decode_err
    end

    -- Compatibility fallback for a temporary endpoint/server regression.
    local story_url = story.url:gsub("#.*$", ""):gsub("%?.*$", "")
    local page_url = page == 1 and story_url or (story_url .. "?page=" .. page)
    local html, page_err = self:authGet(page_url)
    if html then return html, nil, true end
    return nil, page_err or endpoint_err
end

function Source:getStoryPage(story, page)
    page = page or 1
    local html, err, used_full_page = self:getChapterListHtml(story, page)
    if not html then return nil, err end
    return self:parseStoryPage(html, story, page, used_full_page)
end

function Source:getAllChapters(story, progress_cb)
    local first_html, err = self:getChapterListHtml(story, 1)
    if not first_html then return nil, err end
    local total_pages = chapterPageCount(first_html)
    local all_chapters = {}
    local seen_chapter_urls = {}

    for page = 1, total_pages do
        if progress_cb then
            progress_cb(string.format(
                "Lấy danh sách chương trang %d/%d...",
                page,
                total_pages
            ))
        end

        local html, page_err
        if page == 1 then
            html = first_html
        else
            html, page_err = self:getChapterListHtml(story, page)
        end
        if not html then
            return nil, string.format(
                "Không thể lấy danh sách chương trang %d/%d: %s",
                page,
                total_pages,
                tostring(page_err or "lỗi không xác định")
            )
        end

        local parsed = self:parseStoryPage(html, story, page)
        if #parsed.chapters == 0 then
            return nil, string.format(
                "Trang chương %d/%d không có dữ liệu; đã hủy để tránh tải thiếu",
                page,
                total_pages
            )
        end
        for _, chapter in ipairs(parsed.chapters) do
            if seen_chapter_urls[chapter.url] then
                return nil, string.format(
                    "Trang chương %d/%d trả dữ liệu trùng; đã hủy để tránh tải thiếu",
                    page,
                    total_pages
                )
            end
            seen_chapter_urls[chapter.url] = true
            all_chapters[#all_chapters + 1] = chapter
        end
    end

    return all_chapters
end

function Source:parseChapter(html, chapter)
    if isVipLocked(html) then return nil, vipError() end
    if not html or #html < 50 then return nil, "Không nhận được nội dung từ AkayTruyen" end

    local chapter_title = html:match(
        '<h1[^>]-class=["\'][^"\']*custom%-text[^"\']*["\'][^>]*>'
            .. "([%s%S]-)</h1>"
    ) or html:match("<h[12][^>]*>([%s%S]-)</h[12]>")

    local content
    local content_id_at = html:find('id="chapter-content"', 1, true)
        or html:find("id='chapter-content'", 1, true)
    if content_id_at then
        local content_start = html:find(">", content_id_at, true)
        if content_start then
            content_start = content_start + 1
            local nav_start = html:find(
                '<div class="chapter-nav',
                content_start,
                true
            ) or html:find(
                "<div class='chapter-nav",
                content_start,
                true
            )
            if nav_start then
                content = html:sub(content_start, nav_start - 1)
                -- Remove only the chapter-content wrapper's final closing tag.
                content = content:gsub("%s*</div>%s*$", "")
            end
        end
    end

    -- Layout fallback for old or temporarily changed Akay templates.
    content = content
        or html:match('<div[^>]-id="chapter%-content"[^>]*>([%s%S]-)</div>')
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

function Source:getChapterAsync(chapter)
    local html, err = self:authGetAsync(chapter.url)
    if not html then return nil, err end
    return self:parseChapter(html, chapter)
end

return Source
