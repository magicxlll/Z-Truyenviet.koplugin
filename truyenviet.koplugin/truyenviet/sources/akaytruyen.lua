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
}

local function parseCookies(headers)
    local cookies = {}
    if not headers then
        return cookies
    end
    local raw = headers["set-cookie"] or headers["Set-Cookie"]
    if type(raw) == "string" then
        for name, value in raw:gmatch("([%w_%-]+)=([^;,]+)") do
            local lower_name = name:lower()
            if lower_name ~= "expires"
                    and lower_name ~= "path"
                    and lower_name ~= "max-age"
                    and lower_name ~= "domain"
                    and lower_name ~= "samesite" then
                cookies[name] = value
            end
        end
    elseif type(raw) == "table" then
        for _, cookie_string in ipairs(raw) do
            local name, value = cookie_string:match("^%s*([^=]+)=([^;]*)")
            if name then
                cookies[name] = value
            end
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
    return html
        and (
            html:match(
                '<div[^>]-class=["\'][^"\']*access%-denied%-container'
            )
            or html:find("Chương này dành cho tài khoản VIP", 1, true)
        )
end

local function vipError()
    return "Chương VIP bị khóa. Hãy đăng nhập tài khoản AkayTruyen có quyền "
        .. "VIP trong Quản lý nguồn. Plugin không thể tải nội dung nếu tài "
        .. "khoản chưa được cấp quyền."
end

function Source:getCoverHeaders()
    local headers = {
        ["Referer"] = self.base_url .. "/",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    }
    local cookie = cookieHeader(self._cookies)
    if cookie then
        headers["Cookie"] = cookie
    end
    return headers
end

-- Akay trả 500 cho trang truyện/chương khi gửi X-Requested-With. Giữ một
-- bộ header HTML rõ ràng để mọi request đọc nội dung luôn giống trình duyệt.
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
    local content, err, response_headers, code = Http:request(
        "POST",
        url,
        body,
        request_headers,
        options
    )
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

    local csrf_token = login_html:match(
        'name="_token"%s+value="([^"]+)"'
    ) or login_html:match(
        'name="_token"%s+value=\'([^\']+)\''
    ) or login_html:match(
        'name="csrf%-token"%s+content="([^"]+)"'
    )
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

    local location = response_headers
        and (response_headers.location or response_headers.Location)
        or ""
    if not code or code < 300 or code >= 400
            or location:find("/login", 1, true) then
        return nil, "Đăng nhập AkayTruyen thất bại: "
            .. tostring(post_err or "sai email/mật khẩu")
    end

    local account_html, account_err = self:authGet(self.base_url .. "/")
    if not account_html then
        return nil, "Không thể xác minh phiên đăng nhập: "
            .. tostring(account_err)
    end
    local has_logout_form = account_html:match(
        '<form[^>]-action="[^"]*/logout"'
    ) ~= nil
    if not has_logout_form then
        return nil, "Đăng nhập AkayTruyen không thành công"
    end

    self._logged_in = true
    return true
end

function Source:ensureLoggedIn()
    if self._logged_in and cookieHeader(self._cookies) then
        return true
    end
    local CredentialManager = require("truyenviet/credential_manager")
    local credential = CredentialManager:getCredential(self.id)
    if not credential then
        return nil, "Chưa lưu tài khoản AkayTruyen"
    end
    return self:login(credential.username, credential.password)
end

function Source:isLoggedIn()
    return self._logged_in == true
end

function Source:parseSearch(html)
    local stories = {}
    local seen = {}

    -- AkayTruyen tách anchor ảnh bìa và anchor tiêu đề. Gom tiêu đề trước
    -- để anchor ảnh đầu tiên không khóa một kết quả có tiêu đề rỗng.
    local title_by_url = {}
    for anchor_attrs, anchor_html in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
        local href = Util.getAttribute(anchor_attrs, "href")
        if href and href:find("/truyen/", 1, true) then
            local full_url = Util.absoluteUrl(self.base_url, href)
            local class_attr = Util.getAttribute(anchor_attrs, "class") or ""
            if class_attr:find("story-name", 1, true)
                    or class_attr:find("story-title", 1, true) then
                local raw_title = Util.trim(Util.stripTags(anchor_html))
                if raw_title ~= "" then
                    title_by_url[full_url] = raw_title
                end
            end
        end
    end

    for anchor_attrs, anchor_html in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
        local href = Util.getAttribute(anchor_attrs, "href")
        if href and href:find("/truyen/", 1, true) then
            local full_url = Util.absoluteUrl(self.base_url, href)
            if not seen[full_url] then
                seen[full_url] = true
                local title = title_by_url[full_url]
                    or Util.getAttribute(anchor_attrs, "title")
                if not title or title == "" then
                    title = anchor_html:match('<h%d[^>]*>([%s%S]-)</h%d>')
                    if title then
                        title = Util.stripTags(title)
                    else
                        title = Util.stripTags(anchor_html)
                    end
                    title = title:gsub("%s+", " ")
                    title = title:gsub("Full.*$", ""):gsub("Hot.*$", ""):gsub("New.*$", ""):gsub("Đang viết.*$", "")
                    title = Util.trim(title)
                end

                local img_src = anchor_html:match('src="([^"]+)"') or anchor_html:match('data%-src="([^"]+)"')
                if title ~= "" and not title:find("^Truyện") and not title:find("^Thể loại") then
                    table.insert(stories, {
                        source_id = self.id,
                        title = Util.decodeHtml(title),
                        url = full_url,
                        cover_url = img_src and Util.absoluteUrl(self.base_url, img_src) or nil,
                        kind = self.kind,
                    })
                end
            end
        end
    end

    return Util.uniqueBy(stories, "url")
end

function Source:search(query)
    local encoded = ko_util.urlEncode(query):gsub("%%20", "+")
    local html, err = self:authGet(
        self.base_url .. "/tim-kiem?keyword=" .. encoded
    )
    if not html then
        html, err = self:authGet(
            self.base_url .. "/tim-kiem/?tukhoa=" .. encoded
        )
    end
    if not html then
        return nil, err
    end
    return self:parseSearch(html)
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
    local start_at = html:find(start_marker, 1, true)
    if not start_at then
        return ""
    end
    local end_at = end_marker
        and html:find(end_marker, start_at + #start_marker, true)
    return html:sub(start_at, (end_at and end_at - 1) or #html)
end

function Source:parseHomeSection(html, page, start_marker, end_marker, title)
    local section_html = extractHomeSection(html, start_marker, end_marker)
    if section_html == "" then
        return nil, "Không tìm thấy mục danh sách '" .. title .. "' trên AkayTruyen"
    end

    return {
        stories = self:parseSearch(section_html),
        genres = Util.parseGenres(html, self.base_url),
        page = page or 1,
        total_pages = 1,
        title = title,
    }
end

function Source:getHomePage()
    return self:authGet(self.base_url .. "/")
end

function Source:getCompleted(page)
    page = page or 1
    local html, err = self:getHomePage()
    if not html then
        return nil, err
    end
    return self:parseHomeSection(
        html,
        page,
        '<div class="section-stories-full',
        '<div id="id_feedback_button"',
        "Truyện hoàn thành"
    )
end

function Source:getHot(page)
    page = page or 1
    local html, err = self:getHomePage()
    if not html then
        return nil, err
    end
    return self:parseHomeSection(
        html,
        page,
        '<div class="section-stories-hot',
        '<div class="section-stories-new',
        "Truyện hot"
    )
end

function Source:getUpdating(page)
    page = page or 1
    local html, err = self:getHomePage()
    if not html then
        return nil, err
    end
    return self:parseHomeSection(
        html,
        page,
        '<div class="section-stories-new',
        '<div class="section-stories-full',
        "Truyện mới cập nhật"
    )
end

function Source:getGenre(genre, page)
    page = page or 1
    local url = Util.withTrailingSlash(genre.url)
    if page > 1 then
        url = url .. "?page=" .. page
    end
    local html, err = self:authGet(url)
    if not html then
        return nil, err
    end
    local result = self:parseListing(html, page)
    result.title = genre.name
    result.genre = genre
    return result
end

function Source:parseStoryDetails(html)
    local description_html = html:match('<div[^>]-class="[^"]*desc[^"]*"[^>]-itemprop="description"[^>]*>([%s%S]-)</div>')
        or html:match('<div[^>]-class="[^"]*desc[^"]*"[^>]*>([%s%S]-)</div>')
        or html:match('<div[^>]-itemprop="description"[^>]*>([%s%S]-)</div>')

    local author
    for anchor_attrs, anchor_html in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
        if Util.getAttribute(anchor_attrs, "itemprop") == "author" or anchor_attrs:find("author") then
            author = Util.stripTags(anchor_html)
            break
        end
    end

    return {
        description = description_html and Util.stripTags(description_html) or Util.getMetaContent(html, "name", "description"),
        author = author or "Tác Giả",
        status = "Đang cập nhật",
        genres = Util.parseGenreNames(html),
    }
end

function Source:getStoryDetails(story)
    local html, err = self:authGet(story.url)
    if not html then
        return nil, err
    end
    return self:parseStoryDetails(html)
end

function Source:parseStoryPage(html, story, page)
    local chapters = {}
    local story_url_clean = story.url:gsub("%?.*$", ""):gsub("/$", "")
    local story_slug = story_url_clean:match("([^/]+)$")
    local chapter_url_prefix = self.base_url:gsub("/$", "") .. "/" .. story_slug .. "/"

    for anchor_attrs, anchor_html in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
        local href = Util.getAttribute(anchor_attrs, "href")
        if href then
            local abs_href = Util.absoluteUrl(self.base_url, href):gsub("/$", "")
            local class_attr = Util.getAttribute(anchor_attrs, "class") or ""
            local normalized_class = " " .. class_attr:gsub("%s+", " ") .. " "
            local is_chapter_anchor = normalized_class:find(
                " chapter-link-mobile ",
                1,
                true
            ) ~= nil
                or anchor_html:find("chapter-number", 1, true) ~= nil
                or anchor_html:find("chapter-title", 1, true) ~= nil

            -- AkayTruyen dùng song song URL mới /chuong-N-slug và URL legacy
            -- /N-slug hoặc /slug. Class chapter-link-mobile là dấu hiệu ổn định
            -- để phân biệt chúng với link hành động/giới thiệu cùng prefix truyện.
            local has_story_prefix = abs_href:sub(1, #chapter_url_prefix)
                == chapter_url_prefix
            local href_tail = has_story_prefix
                and abs_href:sub(#chapter_url_prefix + 1)
                or ""
            local is_chapter_href = href_tail ~= ""
                and not href_tail:find("/", 1, true)
                and not href_tail:find("?", 1, true)
                and not href_tail:find("#", 1, true)

            if is_chapter_anchor and is_chapter_href then
                local num = anchor_html:match('<div[^>]-class="chapter%-number"[^>]*>([%s%S]-)</div>')
                local title_part = anchor_html:match('<div[^>]-class="chapter%-title"[^>]*>([%s%S]-)</div>')
                local title
                if num or title_part then
                    local clean_num = num and Util.stripTags(num) or ""
                    local clean_part = title_part and Util.stripTags(title_part) or ""
                    if clean_num ~= "" and clean_part ~= "" then
                        local stripped_num = clean_num:gsub("^%s*[Cc]hương%s*", "")
                        if stripped_num ~= ""
                                and clean_part:find(
                                    stripped_num:gsub("^0+", ""),
                                    1,
                                    true
                                ) then
                            title = clean_part
                        else
                            title = clean_num .. ": " .. clean_part
                        end
                    else
                        title = clean_num ~= "" and clean_num or clean_part
                    end
                else
                    title = Util.stripTags(anchor_html)
                end

                -- Loại bỏ các ký tự badge ngày tháng rác như 27 T2, 07 T3, 15/02
                title = title:gsub("^%s*%d+%s*T%d+%s*", "")
                title = title:gsub("^%s*%d+/%d+%s*", "")
                title = title:gsub("^%s*%d+%s*[A-Za-z]?%d*%s*", "")

                title = Util.decodeHtml(Util.trim(title:gsub("%s+", " ")))
                if title == "" then
                    title = Util.getAttribute(anchor_attrs, "title") or "Chương"
                end

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

    local unique_chapters = Util.uniqueBy(chapters, "url")

    local total_pages = tonumber(html:match('class="jump%-input[^"]*"[^>]-max="(%d+)"')) or 1
    if total_pages == 1 then
        for p in html:gmatch('page=(%d+)') do
            total_pages = math.max(total_pages, tonumber(p) or 1)
        end
    end

    story.details = self:parseStoryDetails(html)
    return {
        story = story,
        chapters = unique_chapters,
        page = page or 1,
        total_pages = total_pages,
    }
end

function Source:getStoryPage(story, page)
    page = page or 1
    local story_url = story.url:gsub("%?.*$", "")
    local page_url = page == 1 and story_url or (story_url .. "?page=" .. page)

    local html, err = self:authGet(page_url)
    if not html then
        return nil, err
    end

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

    local all_chapters = {}
    local seen_chapter_urls = {}
    for p = 1, total_pages do
        if progress_cb then
            progress_cb(string.format("Lấy danh sách chương trang %d/%d...", p, total_pages))
        end
        local p_url = p == 1 and story_url or (story_url .. "?page=" .. p)
        local html
        local page_err
        if p == 1 then
            html = first_html
        else
            html, page_err = self:authGet(p_url)
        end
        if not html then
            return nil, string.format(
                "Không thể lấy danh sách chương trang %d/%d: %s",
                p,
                total_pages,
                tostring(page_err or "lỗi không xác định")
            )
        end

        local page_res = self:parseStoryPage(html, story, p)
        if #page_res.chapters == 0 then
            return nil, string.format(
                "Trang chương %d/%d không có dữ liệu; đã hủy để tránh tải thiếu",
                p,
                total_pages
            )
        end
        for _, ch in ipairs(page_res.chapters) do
            if seen_chapter_urls[ch.url] then
                return nil, string.format(
                    "Trang chương %d/%d trả dữ liệu trùng; đã hủy để tránh tải thiếu",
                    p,
                    total_pages
                )
            end
            seen_chapter_urls[ch.url] = true
            table.insert(all_chapters, ch)
        end
    end

    return all_chapters
end

function Source:parseChapter(html, chapter)
    if isVipLocked(html) then
        return nil, vipError()
    end

    local chapter_title = html:match("<h[12][^>]*>([%s%S]-)</h[12]>")

    local content = html:match('<div[^>]-id="chapter%-content"[^>]*>([%s%S]-)</div>')
        or html:match('<div[^>]-class="[^"]*chapter%-content[^"]*"[^>]- >([%s%S]-)</div>')
        or html:match('<div[^>]-id="chapter%-c"[^>]*>([%s%S]-)</div>')

    if not content then
        return nil, "Không tìm thấy nội dung chương"
    end

    content = Util.sanitizeContentHtml(content)

    local previous_url
    local next_url
    for anchor_attrs in html:gmatch("<a([^>]*)>") do
        local id = Util.getAttribute(anchor_attrs, "id")
        local href = Util.getAttribute(anchor_attrs, "href")
        if href and not href:find("^javascript:") then
            if id == "prev_chap" then
                previous_url = Util.absoluteUrl(self.base_url, href)
            end
            if id == "next_chap" then
                next_url = Util.absoluteUrl(self.base_url, href)
            end
        end
    end
    if not previous_url or not next_url then
        for anchor_attrs, anchor_body in html:gmatch("<a([^>]-)>([%s%S]-)</a>") do
            local href = Util.getAttribute(anchor_attrs, "href")
            if href and not href:find("^javascript:") then
                if not previous_url
                        and (anchor_body:find("chevron-left", 1, true)
                            or anchor_body:find("arrow-left", 1, true)
                            or anchor_body:find(
                                "fa-chevron-circle-left",
                                1,
                                true
                            )) then
                    previous_url = Util.absoluteUrl(self.base_url, href)
                end
                if not next_url
                        and (anchor_body:find("chevron-right", 1, true)
                            or anchor_body:find("arrow-right", 1, true)
                            or anchor_body:find(
                                "fa-chevron-circle-right",
                                1,
                                true
                            )) then
                    next_url = Util.absoluteUrl(self.base_url, href)
                end
            end
        end
    end

    return {
        title = chapter_title and Util.stripTags(chapter_title) or chapter.title,
        content = content,
        previous_url = previous_url,
        next_url = next_url,
        url = chapter.url,
        kind = self.kind,
    }
end

function Source:getChapter(chapter)
    local html, err = self:authGet(chapter.url)
    if not html then
        return nil, err
    end
    if isVipLocked(html) and not self:isLoggedIn() then
        local CredentialManager = require("truyenviet/credential_manager")
        if CredentialManager:hasCredential(self.id) then
            local logged_in, login_err = self:ensureLoggedIn()
            if logged_in then
                html, err = self:authGet(chapter.url)
                if not html then
                    return nil, err
                end
            else
                return nil, vipError() .. "\nĐăng nhập thất bại: "
                    .. tostring(login_err)
            end
        end
    end
    return self:parseChapter(html, chapter)
end

return Source
