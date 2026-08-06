local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local ko_util = require("util")

local GenericSource = {}

function GenericSource.create(schema)
    local source = {
        id = schema.id or "custom_source",
        name = schema.name or "Custom Source",
        kind = schema.kind or "text",
        base_url = schema.base_url or "",
        headers = schema.headers or {},
        schema = schema,
    }

    function source:getCoverHeaders()
        local headers = {
            ["Referer"] = self.base_url .. "/",
        }
        if self.headers then
            for k, v in pairs(self.headers) do
                headers[k] = v
            end
        end
        return headers
    end

    function source:getHeaders()
        return self:getCoverHeaders()
    end

    function source:parseSearch(html)
        local stories = {}
        local s_conf = self.schema.search or {}
        local position = 1

        -- Phương án A: Quét theo block truyện
        if s_conf.story_block_pattern then
            for block in html:gmatch(s_conf.story_block_pattern) do
                local href = s_conf.url_pattern and block:match(s_conf.url_pattern)
                local title = s_conf.title_pattern and block:match(s_conf.title_pattern)
                local cover = s_conf.cover_pattern and (block:match(s_conf.cover_pattern) or block:match('src="([^"]+)"'))
                
                if href and title then
                    table.insert(stories, {
                        source_id = self.id,
                        title = Util.decodeHtml(Util.stripTags(title)),
                        url = Util.absoluteUrl(self.base_url, href),
                        cover_url = cover and Util.absoluteUrl(self.base_url, cover) or nil,
                        kind = self.kind,
                    })
                end
            end
        end

        -- Phương án B: Fallback tìm thẻ <h3> hoặc <a> chứa link & title
        if #stories == 0 then
            for anchor_attrs, anchor_html in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
                local href = Util.getAttribute(anchor_attrs, "href")
                local title = Util.getAttribute(anchor_attrs, "title") or Util.stripTags(anchor_html)
                if href and title ~= "" and (href:find("/truyen/", 1, true) or href:find("/story/", 1, true) or href:find("%-[%d]+/?$")) then
                    local img_src = anchor_html:match('src="([^"]+)"') or anchor_html:match('data%-src="([^"]+)"')
                    table.insert(stories, {
                        source_id = self.id,
                        title = Util.decodeHtml(title),
                        url = Util.absoluteUrl(self.base_url, href),
                        cover_url = img_src and Util.absoluteUrl(self.base_url, img_src) or nil,
                        kind = self.kind,
                    })
                end
            end
        end

        -- Phương án C: Fallback bóc tách từ Next.js RSC JSON State (cho vireal.vn, storya.click...)
        if #stories == 0 then
            local norm_html = html:gsub('\\"', '"'):gsub("\\/", "/")
            local seen = {}
            for prefix, slug in norm_html:gmatch("/(story)/([%w%-]+)") do
                if not seen[slug] and #slug > 3 then
                    seen[slug] = true
                    local title = norm_html:match('"name"%s*:%s*"([^"]+)"[^{}]*' .. slug)
                        or norm_html:match('"alt"%s*:%s*"([^"]+)"[^{}]*' .. slug)
                        or norm_html:match(slug .. '[^{}]*"alt"%s*:%s*"([^"]+)"')
                        or norm_html:match(slug .. '[^{}]*"name"%s*:%s*"([^"]+)"')
                        or slug:gsub("%-", " ")

                    local cover = norm_html:match('"thumbnail"%s*:%s*"([^"]+)"[^{}]*' .. slug)
                        or norm_html:match('"src"%s*:%s*"(https?://[^"]+)"[^{}]*' .. slug)

                    table.insert(stories, {
                        source_id = self.id,
                        title = Util.decodeHtml(Util.stripTags(title)),
                        url = Util.absoluteUrl(self.base_url, "/" .. prefix .. "/" .. slug),
                        cover_url = cover and Util.absoluteUrl(self.base_url, cover) or nil,
                        kind = self.kind,
                    })
                end
            end

            for prefix, slug in norm_html:gmatch("/(truyen)/([%w%-]+)") do
                if not seen[slug] and #slug > 3 then
                    seen[slug] = true
                    local title = norm_html:match('"name"%s*:%s*"([^"]+)"[^{}]*' .. slug)
                        or norm_html:match('"alt"%s*:%s*"([^"]+)"[^{}]*' .. slug)
                        or norm_html:match(slug .. '[^{}]*"alt"%s*:%s*"([^"]+)"')
                        or norm_html:match(slug .. '[^{}]*"name"%s*:%s*"([^"]+)"')
                        or slug:gsub("%-", " ")

                    local cover = norm_html:match('"thumbnail"%s*:%s*"([^"]+)"[^{}]*' .. slug)
                        or norm_html:match('"src"%s*:%s*"(https?://[^"]+)"[^{}]*' .. slug)

                    table.insert(stories, {
                        source_id = self.id,
                        title = Util.decodeHtml(Util.stripTags(title)),
                        url = Util.absoluteUrl(self.base_url, "/" .. prefix .. "/" .. slug),
                        cover_url = cover and Util.absoluteUrl(self.base_url, cover) or nil,
                        kind = self.kind,
                    })
                end
            end
        end

        if #stories == 0 then
            local error_msg = "Lỗi Parse 0 truyện từ nguồn " .. self.name
            if html:find("Cloudflare", 1, true) or html:find("Just a moment", 1, true) then
                error_msg = error_msg .. " - Bị Cloudflare block"
            end
            table.insert(stories, {
                source_id = self.id,
                title = error_msg,
                url = self.base_url,
                kind = self.kind,
            })
        end

        return Util.uniqueBy(stories, "url")
    end

    function source:search(query)
        local s_conf = self.schema.search or {}
        local path = s_conf.path or "/tim-kiem/?tukhoa={query}"
        local encoded = Util.urlEncode(query):gsub("%%20", "+")
        local url = self.base_url .. path:gsub("{query}", function() return encoded end)
        
        local html, err = Http:get(url, self:getHeaders())
        if not html then
            return nil, err
        end
        return self:parseSearch(html)
    end

    function source:parseListing(html, page)
        return {
            stories = self:parseSearch(html),
            genres = Util.parseGenres(html, self.base_url),
            page = page or 1,
            total_pages = Util.maxPage(html, page),
        }
    end

    function source:getCompleted(page)
        page = page or 1
        local c_conf = self.schema.completed or {}
        local path = c_conf.path or "/"
        local url = self.base_url
        if path ~= "/" and path ~= "" then
            url = self.base_url .. path
        end
        if page > 1 then
            if url:find("%?") then
                url = url .. "&page=" .. page
            else
                url = Util.withTrailingSlash(url) .. "trang-" .. page .. "/"
            end
        end
        local html, err = Http:get(url, self:getHeaders())
        if not html then
            -- Fallback thử lại ở trang chủ
            html, err = Http:get(self.base_url, self:getHeaders())
            if not html then
                return nil, err
            end
        end
        local result = self:parseListing(html, page)
        result.title = "Truyện mới cập nhật"
        return result
    end


    function source:getGenre(genre, page)
        page = page or 1
        local raw_url = genre and (genre.url or genre.path) or "/"
        local abs_url = Util.absoluteUrl(self.base_url, raw_url)
        local url = Util.withTrailingSlash(abs_url)
        if page > 1 then
            if url:find("%?") then
                url = url .. "&page=" .. page
            else
                url = url .. "trang-" .. page .. "/"
            end
        end
        local html, err = Http:get(url, self:getHeaders())
        if not html then
            return self:getCompleted(page)
        end
        local result = self:parseListing(html, page)
        result.title = genre and genre.name or "Thể loại"
        result.genre = genre
        return result
    end

    function source:getHot(page)
        page = page or 1
        local h_conf = self.schema.hot or {}
        local path = h_conf.path or "/danh-sach/truyen-hot/"
        local url = self.base_url
        if path ~= "/" and path ~= "" then
            url = self.base_url .. path
        end
        if page > 1 then
            if url:find("%?") then
                url = url .. "&page=" .. page
            else
                url = Util.withTrailingSlash(url) .. "trang-" .. page .. "/"
            end
        end
        local html, err = Http:get(url, self:getHeaders())
        if not html then
            return self:getCompleted(page)
        end
        local result = self:parseListing(html, page)
        result.title = "Truyện Hot / Đề Cử"
        return result
    end

    function source:getUpdating(page)
        page = page or 1
        local u_conf = self.schema.updating or {}
        local path = u_conf.path or "/danh-sach/truyen-moi/"
        local url = self.base_url
        if path ~= "/" and path ~= "" then
            url = self.base_url .. path
        end
        if page > 1 then
            if url:find("%?") then
                url = url .. "&page=" .. page
            else
                url = Util.withTrailingSlash(url) .. "trang-" .. page .. "/"
            end
        end
        local html, err = Http:get(url, self:getHeaders())
        if not html then
            return self:getCompleted(page)
        end
        local result = self:parseListing(html, page)
        result.title = "Truyện Mới Cập Nhật"
        return result
    end

    function source:getSections()
        return {
            { id = "hot", name = "🔥 Truyện Hot / Đề Cử" },
            { id = "completed", name = "✅ Truyện Hoàn Thành (Full)" },
            { id = "updating", name = "🆕 Truyện Đang Ra / Cập Nhật Mới" },
            { id = "genres", name = "📚 Tất Cả Thể Loại" },
            { id = "search", name = "🔍 Tìm Kiếm Trên Nguồn Này" },
        }
    end

    function source:parseStoryDetails(html)
        local d_conf = self.schema.story_details or {}
        local desc
        if d_conf.description_pattern then
            desc = html:match(d_conf.description_pattern)
        end
        if not desc then
            desc = Util.getMetaContent(html, "name", "description") or Util.getMetaContent(html, "property", "og:description")
        end

        local author
        if d_conf.author_pattern then
            author = html:match(d_conf.author_pattern)
        end
        if author then
            author = Util.stripTags(author)
        end

        local status
        if d_conf.status_pattern then
            status = html:match(d_conf.status_pattern)
        end

        return {
            description = desc and Util.stripTags(desc) or "",
            author = author,
            status = status and Util.stripTags(status) or "Đang cập nhật",
            genres = Util.parseGenreNames(html),
        }
    end

    function source:getStoryDetails(story)
        local html, err = Http:get(story.url, self:getHeaders())
        if not html then
            return nil, err
        end
        return self:parseStoryDetails(html)
    end

    function source:parseStoryPage(html, story, page)
        local sp_conf = self.schema.story_page or {}
        local chapters = {}

        if sp_conf.chapter_item_pattern then
            for href, title in html:gmatch(sp_conf.chapter_item_pattern) do
                table.insert(chapters, {
                    title = Util.stripTags(Util.decodeHtml(title)),
                    url = Util.absoluteUrl(self.base_url, href),
                    source_id = self.id,
                    story_url = story.url,
                    kind = self.kind,
                })
            end
        end

        -- Fallback nếu không có chapter_item_pattern
        if #chapters == 0 then
            for anchor_attrs, anchor_html in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
                local href = Util.getAttribute(anchor_attrs, "href")
                if href and (href:find("/chuong-", 1, true) or href:find("/chapter-", 1, true)) then
                    local title = Util.stripTags(anchor_html)
                    table.insert(chapters, {
                        title = title ~= "" and title or Util.getAttribute(anchor_attrs, "title") or "Chương",
                        url = Util.absoluteUrl(self.base_url, href),
                        source_id = self.id,
                        story_url = story.url,
                        kind = self.kind,
                    })
                end
            end
        end

        -- Fallback bóc tách từ Next.js RSC JSON State (cho vireal.vn...)
        if #chapters == 0 then
            local norm_html = html:gsub('\\"', '"'):gsub("\\/", "/")
            local seen_chap = {}
            for name, slug in norm_html:gmatch('"name"%s*:%s*"([^"]+)"%s*,%s*"slug"%s*:%s*"([^"]+)"') do
                if not seen_chap[slug] and (slug:find("chuong") or slug:find("chapter") or name:find("Chương")) then
                    seen_chap[slug] = true
                    local story_slug = story.url:match("/story/([^/?]+)") or story.url:match("/truyen/([^/?]+)") or ""
                    local full_chap_url = Util.absoluteUrl(self.base_url, "/story/" .. story_slug .. "/" .. slug)
                    table.insert(chapters, {
                        title = Util.decodeHtml(Util.stripTags(name)),
                        url = full_chap_url,
                        source_id = self.id,
                        story_url = story.url,
                        kind = self.kind,
                    })
                end
            end
            if #chapters == 0 then
                for slug in norm_html:gmatch('(chuong%-[%a%d%-]+)') do
                    if not seen_chap[slug] then
                        seen_chap[slug] = true
                        local story_slug = story.url:match("/story/([^/?]+)") or story.url:match("/truyen/([^/?]+)") or ""
                        local full_chap_url = Util.absoluteUrl(self.base_url, "/story/" .. story_slug .. "/" .. slug)
                        table.insert(chapters, {
                            title = slug:gsub("%-", " "),
                            url = full_chap_url,
                            source_id = self.id,
                            story_url = story.url,
                            kind = self.kind,
                        })
                    end
                end
            end
        end

        -- Fallback bóc tách cho metruyenchuvn.org qua API /get/listchap/{story_id}
        if #chapters == 0 then
            local story_id = html:match("page%s*%(%s*(%d+)")
                or html:match("data%-id=[\"'](%d+)[\"']")
                or html:match("id=[\"']book_id[\"']%s*value=[\"'](%d+)[\"']")

            if story_id then
                local seen_chap = {}
                local Http = require("truyenviet/http_client")
                local page_num = 1
                while page_num <= 50 do
                    local api_url = Util.absoluteUrl(self.base_url, "/get/listchap/" .. story_id .. "?page=" .. page_num)
                    local json_str = Http:get(api_url, {
                        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                    })
                    if not json_str or #json_str < 30 then break end

                    json_str = json_str:gsub('\\u003c', '<'):gsub('\\u003e', '>'):gsub('\\u0027', "'"):gsub('\\u0022', '"'):gsub('\\"', '"'):gsub('\\/', '/')
                    local found_count = 0
                    for chap_url, chap_title in json_str:gmatch('<a[^>]+href=[\'"]([^\'"]+)[\'"][^>]*>([%s%S]-)</a>') do
                        if not seen_chap[chap_url] then
                            seen_chap[chap_url] = true
                            found_count = found_count + 1
                            local full_chap_url = Util.absoluteUrl(self.base_url, chap_url)
                            table.insert(chapters, {
                                title = Util.decodeHtml(Util.stripTags(chap_title)),
                                url = full_chap_url,
                                source_id = self.id,
                                story_url = story.url,
                                kind = self.kind,
                            })
                        end
                    end
                    if found_count == 0 then break end
                    page_num = page_num + 1
                end
            end
        end

        local total_pages = 1
        if sp_conf.total_pages_pattern then
            total_pages = tonumber(html:match(sp_conf.total_pages_pattern)) or 1
        else
            total_pages = Util.maxPage(html, page)
        end

        local unique_chaps = Util.uniqueBy(chapters, "url")
        local reversed_chaps = {}
        for i = #unique_chaps, 1, -1 do
            table.insert(reversed_chaps, unique_chaps[i])
        end

        story.details = self:parseStoryDetails(html)
        return {
            story = story,
            chapters = reversed_chaps,
            page = page or 1,
            total_pages = total_pages,
        }

    end

    function source:getStoryPage(story, page)
        page = page or 1
        local story_url = story.url:gsub("%?.*$", "")
        local first_html, err = Http:get(story_url, self:getHeaders())
        if not first_html then
            return nil, err
        end

        local total_pages = tonumber(first_html:match('class="jump%-input[^"]*"[^>]-max="(%d+)"'))
            or tonumber(first_html:match('page=(%d+)'))
            or Util.maxPage(first_html, 1)

        local target_web_page = total_pages - page + 1
        if target_web_page < 1 then
            target_web_page = 1
        end

        local page_url = target_web_page == 1 and story_url or (story_url .. "?page=" .. target_web_page)
        local page_html = first_html
        if target_web_page ~= 1 then
            local res, fetch_err = Http:get(page_url, self:getHeaders())
            if res then
                page_html = res
            end
        end

        return self:parseStoryPage(page_html, story, page)
    end


    function source:parseChapter(html, chapter)
        local c_conf = self.schema.chapter or {}
        local chapter_title
        if c_conf.title_pattern then
            chapter_title = html:match(c_conf.title_pattern)
        end

        local content
        if c_conf.content_pattern then
            content = html:match(c_conf.content_pattern)
        end

        if not content then
            -- Fallback các container thông dụng
            content = html:match('<div[^>]-class="[^"]*truyen[^"]*"[^>]*>(.-)</div>%s*</div>%s*<div')
                or html:match('<div[^>]-class="[^"]*truyen[^"]*"[^>]*>(.-)<footer')
                or html:match('<div[^>]-class="[^"]*chapter%-content[^"]*"[^>]*>(.+)</div>')
                or html:match('<div[^>]-class="[^"]*reading%-content[^"]*"[^>]*>(.+)</div>')
                or html:match('<div[^>]-class="[^"]*cha%-content[^"]*"[^>]*>(.+)</div>')
                or html:match('<div[^>]-id="chapter%-c"[^>]*>(.+)</div>')
                or html:match('<div[^>]-class="[^"]*entry%-content[^"]*"[^>]*>(.+)</div>')
                or html:match('<div[^>]-class="[^"]*post%-content[^"]*"[^>]*>(.+)</div>')
                or html:match('<article[^>]*>(.+)</article>')
        end

        if not content or #Util.stripTags(content) < 50 then
            local norm_html = html:gsub('\\"', '"'):gsub("\\/", "/")
            local json_content = norm_html:match('"content"%s*:%s*"([^"]+)"')
            if json_content and #json_content > 100 then
                json_content = json_content:gsub("\\n", "\n"):gsub("\\r", ""):gsub('\\"', '"'):gsub("\\/", "/")
                if not json_content:find("<p>") then
                    local paragraphs = {}
                    for line in json_content:gmatch("[^\r\n]+") do
                        line = Util.trim(line)
                        if #line > 0 then
                            table.insert(paragraphs, "<p>" .. Util.escapeHtml(line) .. "</p>")
                        end
                    end
                    content = table.concat(paragraphs, "\n")
                else
                    content = json_content
                end
            end
        end

        if not content or #Util.stripTags(content) < 50 then
            local paragraphs = {}
            for p in html:gmatch("<p[^>]*>([%s%S]-)</p>") do
                local clean = Util.stripTags(p):gsub("^%s*", ""):gsub("%s*$", "")
                if #clean > 15 and not clean:find("Copyright") and not clean:find("Trang chủ") then
                    table.insert(paragraphs, "<p>" .. p .. "</p>")
                end
            end
            if #paragraphs >= 3 then
                content = table.concat(paragraphs, "\n")
            end
        end

        if not content or content == "" then
            return nil, "Không tìm thấy nội dung chương"
        end

        content = Util.sanitizeContentHtml(content)

        local previous_url
        local next_url
        if c_conf.prev_url_pattern then
            previous_url = html:match(c_conf.prev_url_pattern)
        end
        if c_conf.next_url_pattern then
            next_url = html:match(c_conf.next_url_pattern)
        end

        if not previous_url or not next_url then
            for anchor_attrs in html:gmatch("<a([^>]*)>") do
                local id = Util.getAttribute(anchor_attrs, "id")
                local href = Util.getAttribute(anchor_attrs, "href")
                if href and not href:find("^javascript:") then
                    if (id == "prev_chap" or href:find("prev")) and not previous_url then
                        previous_url = Util.absoluteUrl(self.base_url, href)
                    elseif (id == "next_chap" or href:find("next")) and not next_url then
                        next_url = Util.absoluteUrl(self.base_url, href)
                    end
                end
            end
        end

        return {
            title = chapter_title and Util.stripTags(chapter_title) or chapter.title,
            content = content,
            previous_url = previous_url and Util.absoluteUrl(self.base_url, previous_url) or nil,
            next_url = next_url and Util.absoluteUrl(self.base_url, next_url) or nil,
            url = chapter.url,
            kind = self.kind,
        }
    end

    function source:getChapter(chapter)
        local html, err = Http:get(chapter.url, self:getHeaders())
        if not html then
            return nil, err
        end
        return self:parseChapter(html, chapter)
    end

    function source:getChapterAsync(chapter)
        local html, err = Http:requestAsync("GET", chapter.url, self:getHeaders(), nil)
        if not html then
            return nil, err
        end
        return self:parseChapter(html, chapter)
    end

    return source
end

return GenericSource
