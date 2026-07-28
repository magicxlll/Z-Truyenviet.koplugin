local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local ko_util = require("util")

local Source = {
    id = "akaytruyen",
    name = "AkayTruyen",
    kind = "text",
    base_url = "https://akaytruyen.com",
}

function Source:getCoverHeaders()
    return {
        ["Referer"] = self.base_url .. "/",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        ["X-Requested-With"] = "XMLHttpRequest",
    }
end

function Source:parseSearch(html)
    local stories = {}
    local seen = {}

    -- Bước 1: Gom map URL truyện -> tiêu đề lấy từ anchor tên truyện
    -- (akaytruyen tách riêng: anchor ảnh bìa + anchor tiêu đề trong <h3>)
    local title_by_url = {}
    for anchor_attrs, anchor_html in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
        local href = Util.getAttribute(anchor_attrs, "href")
        if href and href:find("/truyen/", 1, true) then
            local full_url = Util.absoluteUrl(self.base_url, href)
            local class_attr = Util.getAttribute(anchor_attrs, "class") or ""
            if class_attr:find("story-name", 1, true) or class_attr:find("story-title", 1, true) then
                local raw_title = Util.stripTags(anchor_html)
                raw_title = Util.trim(raw_title)
                if raw_title ~= "" then
                    title_by_url[full_url] = raw_title
                end
            end
        end
    end

    -- Bước 2: Thu thập anchor truyện + ảnh bìa
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
    local html, err = Http:get(self.base_url .. "/tim-kiem?keyword=" .. encoded, self:getCoverHeaders())
    if not html then
        html, err = Http:get(self.base_url .. "/tim-kiem/?tukhoa=" .. encoded, self:getCoverHeaders())
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

function Source:getCompleted(page)
    page = page or 1
    local url = self.base_url .. "/danh-sach/truyen-full"
    if page > 1 then
        url = url .. "?page=" .. page
    end
    local html, err = Http:get(url, self:getCoverHeaders())
    if not html then
        return nil, err
    end
    local result = self:parseListing(html, page)
    result.title = "Truyện hoàn thành"
    return result
end

function Source:getHot(page)
    page = page or 1
    local url = self.base_url .. "/danh-sach/truyen-hot"
    if page > 1 then
        url = url .. "?page=" .. page
    end
    local html, err = Http:get(url, self:getCoverHeaders())
    if not html then
        return nil, err
    end
    local result = self:parseListing(html, page)
    result.title = "Truyện hot"
    return result
end

function Source:getGenre(genre, page)
    page = page or 1
    local url = Util.withTrailingSlash(genre.url)
    if page > 1 then
        url = url .. "?page=" .. page
    end
    local html, err = Http:get(url, self:getCoverHeaders())
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
    local html, err = Http:get(story.url, self:getCoverHeaders())
    if not html then
        return nil, err
    end
    return self:parseStoryDetails(html)
end

function Source:parseStoryPage(html, story, page)
    local chapters = {}
    local story_url_clean = story.url:gsub("%?.*$", ""):gsub("/$", "")

    for anchor_attrs, anchor_html in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
        local href = Util.getAttribute(anchor_attrs, "href")
        if href then
            local abs_href = Util.absoluteUrl(self.base_url, href):gsub("/$", "")
            -- Đường dẫn chương phải có /chuong và khác với URL trang chính truyện
            if abs_href:find("/chuong", 1, true) and abs_href ~= story_url_clean then
                local class_attr = Util.getAttribute(anchor_attrs, "class") or ""
                -- Lọc chính xác anchor chương (chapter-link-mobile) và bỏ các
                -- anchor rác (badge "new-badge", nút phân trang, etc.) dựa
                -- trên cấu trúc class thay vì nội dung văn bản (dễ vỡ).
                local is_chapter_anchor = class_attr:find("chapter-link", 1, true)
                    or anchor_html:find("chapter-number", 1, true)
                    or anchor_html:find("chapter-title", 1, true)

                if is_chapter_anchor then
                    local num = anchor_html:match('<div[^>]-class="chapter%-number"[^>]*>([%s%S]-)</div>')
                    local title_part = anchor_html:match('<div[^>]-class="chapter%-title"[^>]*>([%s%S]-)</div>')
                    local title
                    if num or title_part then
                        local clean_num = num and Util.stripTags(num) or ""
                        local clean_part = title_part and Util.stripTags(title_part) or ""
                        if clean_num ~= "" and clean_part ~= "" then
                            -- Bỏ tiền tố "Chương " nếu cả num và title đều đã chứa
                            local stripped_num = clean_num:gsub("^%s*[Cc]hương%s*", "")
                            if stripped_num ~= "" and clean_part:find(stripped_num:gsub("^0+", ""), 1, true) then
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

    local html, err = Http:get(page_url, self:getCoverHeaders())
    if not html then
        return nil, err
    end

    return self:parseStoryPage(html, story, page)
end

function Source:getAllChapters(story, progress_cb)
    local story_url = story.url:gsub("%?.*$", "")
    local first_html, err = Http:get(story_url, self:getCoverHeaders())
    if not first_html then return nil, err end

    local total_pages = tonumber(first_html:match('class="jump%-input[^"]*"[^>]-max="(%d+)"')) or 1
    if total_pages == 1 then
        for p in first_html:gmatch('page=(%d+)') do
            total_pages = math.max(total_pages, tonumber(p) or 1)
        end
    end

    local all_chapters = {}
    for p = 1, total_pages do
        if progress_cb then
            progress_cb(string.format("Lấy danh sách chương trang %d/%d...", p, total_pages))
        end
        local p_url = p == 1 and story_url or (story_url .. "?page=" .. p)
        local html = (p == 1) and first_html or Http:get(p_url, self:getCoverHeaders())
        if html then
            local page_res = self:parseStoryPage(html, story, p)
            for _, ch in ipairs(page_res.chapters) do
                table.insert(all_chapters, ch)
            end
        end
    end

    return Util.uniqueBy(all_chapters, "url")
end

function Source:parseChapter(html, chapter)
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
    -- akaytruyen dùng nút chevron: <a class="... btn-back-next"><i class="fas fa-chevron-left"></i></a>
    -- và <button disabled ...><i class="fas fa-chevron-right"></i></button> ở chương cuối.
    -- Vẫn fallback theo id cũ (prev_chap/next_chap) để tương thích nếu markup đổi.
    -- Hai pass: pass 1 chỉ xét attrs (icon có thể nằm trong body <i>),
    -- pass 2 xét body để bắt icon class nằm trong thẻ <i> con.
    -- Tách riêng prev/next: nếu dùng `elseif` thì khi tìm thấy prev sẽ không quét
    -- tiếp anchor sau đó để tìm next.
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
                        or anchor_body:find("fa-chevron-circle-left", 1, true)) then
                    previous_url = Util.absoluteUrl(self.base_url, href)
                end
                if not next_url
                    and (anchor_body:find("chevron-right", 1, true)
                        or anchor_body:find("arrow-right", 1, true)
                        or anchor_body:find("fa-chevron-circle-right", 1, true)) then
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
    local html, err = Http:get(chapter.url, self:getCoverHeaders())
    if not html then
        return nil, err
    end
    return self:parseChapter(html, chapter)
end

return Source
