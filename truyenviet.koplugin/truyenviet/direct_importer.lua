local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local Storage = require("truyenviet/storage")
local CredentialManager = require("truyenviet/credential_manager")
local SourceRegistry = require("truyenviet/source_registry")
local Debug = require("truyenviet/debugger")
local ffiutil = require("ffi/util")
local ko_util = require("util")

-- Super Scraper Engine (Kiến Trúc Siêu Cào Tự Động Tạo Nguồn Từ URL)
local DirectImporter = {}

local function extractDomainId(url)
    local host = url:match("https?://([^/]+)") or url
    host = host:gsub("^www%.", "")
    local domain = host:match("([^%.]+)%.[^%.]+$") or host:match("([^%.]+)") or "custom_source"
    domain = domain:gsub("[^%w_]", "_"):lower()
    return domain ~= "" and domain or "custom_source"
end

local function extractHost(url)
    local scheme, host = url:match("^(https?://)([^/]+)")
    if scheme and host then
        return scheme .. host
    end
    return url:gsub("/+$", "")
end

local function cleanHtml(raw)
    if not raw then return "" end
    return raw:gsub('\\"', '"'):gsub("\\/", "/"):gsub("\\\\", "\\")
end

-- Tự động bóc tách thông tin truyện (Meta, OpenGraph, JSON-LD, Tags)
local function extractMetaData(html)
    local meta = {
        title = nil,
        cover = nil,
        description = nil,
        author = nil,
        status = nil,
    }

    if not html or #html < 100 then return meta end
    local norm = cleanHtml(html)

    -- 1. OpenGraph Meta Tags
    meta.title = norm:match('<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']')
        or norm:match('<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:title["\']')
        or norm:match('<meta[^>]+name=["\']twitter:title["\'][^>]+content=["\']([^"\']+)["\']')

    meta.cover = norm:match('<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)["\']')
        or norm:match('<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:image["\']')
        or norm:match('<meta[^>]+name=["\']twitter:image["\'][^>]+content=["\']([^"\']+)["\']')

    meta.description = norm:match('<meta[^>]+property=["\']og:description["\'][^>]+content=["\']([^"\']+)["\']')
        or norm:match('<meta[^>]+name=["\']description["\'][^>]+content=["\']([^"\']+)["\']')

    -- 2. Schema.org JSON-LD parsing
    local json_ld = norm:match('<script[^>]+type=["\']application/ld%+json["\'][^>]*>([%s%S]-)</script>')
    if json_ld then
        local dkjson = require("json")
        local ok, data = pcall(dkjson.decode, json_ld)
        if ok and type(data) == "table" then
            meta.title = meta.title or data.name or data.headline
            meta.description = meta.description or data.description
            if type(data.image) == "string" then
                meta.cover = meta.cover or data.image
            elseif type(data.image) == "table" and data.image.url then
                meta.cover = meta.cover or data.image.url
            end
            if type(data.author) == "table" then
                meta.author = data.author.name
            elseif type(data.author) == "string" then
                meta.author = data.author
            end
        end
    end

    -- 3. DOM Heading Fallbacks
    if not meta.title then
        meta.title = norm:match('<h1[^>]*>([%s%S]-)</h1>') or norm:match('<title>([%s%S]-)</title>')
    end

    if meta.title then meta.title = Util.trim(Util.stripTags(meta.title)) end
    if meta.description then meta.description = Util.trim(Util.stripTags(meta.description)) end

    return meta
end

function DirectImporter:analyzeHtml(html, base_url, domain_id)
    if not html or #html < 200 then
        return nil, "Nội dung HTML quá ngắn hoặc rỗng"
    end

    if html:find("Cloudflare", 1, true) or html:find("Just a moment...", 1, true) then
        return nil, "Trang web bị Cloudflare chống cào (vui lòng bật Firecrawl API)"
    end

    local norm_html = cleanHtml(html)
    local meta = extractMetaData(norm_html)

    -- Đánh giá xem là Truyện Chữ (text) hay Truyện Tranh (manga)
    local is_manga = norm_html:find("chapter%-img") or norm_html:find("page%-chapter")
        or norm_html:find("reading%-detail") or norm_html:find("truyenqq") or norm_html:find("dualeo")

    local kind = is_manga and "manga" or "text"

    -- Xây dựng Schema Siêu Cào tương thích với GenericSource & AkayTruyen Spec
    local schema = {
        id = "auto_" .. domain_id,
        name = base_url:match("https?://([^/]+)") or domain_id,
        kind = kind,
        base_url = base_url,
        headers = {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
            ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ["Referer"] = base_url .. "/",
        },
        matched_template = "Super Scraper Engine v3.7.0",
        search = {
            path = "/tim-kiem?tukhoa={query}",
            story_block_pattern = "<h3[^>]*>([%s%S]-)</h3>",
            title_pattern = "title=[\"']([^\"']+)[\"']",
            url_pattern = "href=[\"']([^\"']+)[\"']",
            cover_pattern = "src=[\"']([^\"']+)[\"']",
        },
        story_details = {
            description_pattern = "<div[^>]-class=[\"'][^\"']*(?:desc|summary|gioi%-thieu|introduce|detail|content)[^\"']*[\"'][^>]*>([%s%S]-)</div>",
            author_pattern = "author",
            status_pattern = "status",
        },
        story_page = {
            chapter_item_pattern = "<a[^>]+href=[\"']([^\"']*/(?:chuong|chapter|c|ch)%-[^\"']*)[\"'][^>]*>([%s%S]-)</a>",
            total_pages_pattern = "trang%-(%d+)",
        },
        chapter = {
            title_pattern = "<h[12][^>]*>([%s%S]-)</h[12]>",
            content_pattern = "<div[^>]-class=[\"'][^\"']*(?:chapter%-content|reading%-content|cha%-content|content|doc%-content|entry%-content)[^\"']*[\"'][^>]*>([%s%S]-)</div>",
            prev_url_pattern = "prev",
            next_url_pattern = "next",
        },
    }

    -- 1. Tự động nhận diện đường dẫn Tìm Kiếm (Search Path)
    if norm_html:find("/?s=", 1, true) then
        schema.search.path = "/?s={query}"
    elseif norm_html:find("/search?q=", 1, true) then
        schema.search.path = "/search?q={query}"
    elseif norm_html:find("/search/", 1, true) then
        schema.search.path = "/search/{query}"
    elseif norm_html:find("/tim-kiem?q=", 1, true) then
        schema.search.path = "/tim-kiem?q={query}"
    end

    -- 2. Tự động nhận diện mẫu chứa Nội Dung Chương (Chapter Content Container)
    if norm_html:find('id="chapter-c"', 1, true) or norm_html:find("id='chapter-c'", 1, true) then
        schema.chapter.content_pattern = "<div[^>]-id=[\"']chapter%-c[\"'][^>]*>(.+)</div>"
    elseif norm_html:find("chapter-content", 1, true) then
        schema.chapter.content_pattern = "<div[^>]-class=[\"'][^\"']*chapter%-content[^\"']*[\"'][^>]*>(.+)</div>"
    elseif norm_html:find("reading-content", 1, true) then
        schema.chapter.content_pattern = "<div[^>]-class=[\"'][^\"']*reading%-content[^\"']*[\"'][^>]*>(.+)</div>"
    elseif norm_html:find("cha-content", 1, true) then
        schema.chapter.content_pattern = "<div[^>]-class=[\"'][^\"']*cha%-content[^\"']*[\"'][^>]*>(.+)</div>"
    elseif norm_html:find('id="content"', 1, true) then
        schema.chapter.content_pattern = "<div[^>]-id=[\"']content[\"'][^>]*>(.+)</div>"
    elseif norm_html:find("box-chap", 1, true) then
        schema.chapter.content_pattern = "<div[^>]-class=[\"'][^\"']*box%-chap[^\"']*[\"'][^>]*>(.+)</div>"
    end

    -- 3. Tự động nhận diện mẫu chứa Danh Sách Chương (Chapter List Items)
    if norm_html:find("/chuong-", 1, true) then
        schema.story_page.chapter_item_pattern = "<a[^>]+href=[\"']([^\"']*/chuong%-[^\"']*)[\"'][^>]*>([%s%S]-)</a>"
    elseif norm_html:find("/chapter-", 1, true) then
        schema.story_page.chapter_item_pattern = "<a[^>]+href=[\"']([^\"']*/chapter%-[^\"']*)[\"'][^>]*>([%s%S]-)</a>"
    elseif norm_html:find("/c-", 1, true) then
        schema.story_page.chapter_item_pattern = "<a[^>]+href=[\"']([^\"']*/c%-[^\"']*)[\"'][^>]*>([%s%S]-)</a>"
    elseif norm_html:find("/doc-truyen/", 1, true) then
        schema.story_page.chapter_item_pattern = "<a[^>]+href=[\"']([^\"']*/doc%-truyen/[^\"']*)[\"'][^>]*>([%s%S]-)</a>"
    end

    return schema, nil, meta
end

function DirectImporter:fetchFirecrawl(url, api_key)
    if not api_key or api_key == "" then
        return nil, "Chưa cài đặt Firecrawl API Key"
    end

    local endpoint = "https://api.firecrawl.dev/v1/scrape"
    local json_body = string.format('{"url": %q, "formats": ["html"]}', url)
    local headers = {
        ["Authorization"] = "Bearer " .. api_key,
        ["Content-Type"] = "application/json",
    }

    Debug.write("[DirectImporter] Requesting Firecrawl API for " .. url)
    local response, err = Http:post(endpoint, json_body, headers)
    if not response then
        return nil, "Lỗi gọi Firecrawl API: " .. tostring(err)
    end

    local dkjson = require("json")
    local ok, parsed = pcall(dkjson.decode, response)
    if not ok or type(parsed) ~= "table" then
        return nil, "Firecrawl trả về JSON không hợp lệ"
    end

    if not parsed.success and parsed.error then
        return nil, "Firecrawl error: " .. tostring(parsed.error)
    end

    local data = parsed.data or parsed
    local html = data and data.html
    if not html or html == "" then
        return nil, "Firecrawl không trả về nội dung HTML"
    end

    return html
end

function DirectImporter:saveSchema(schema)
    Storage:initialize()
    local custom_dir = ffiutil.joinPath(Storage:getRootDir(), "custom_sources")
    ko_util.makePath(custom_dir)

    local file_path = ffiutil.joinPath(custom_dir, schema.id .. ".json")
    local dkjson = require("json")
    local json_str = dkjson.encode(schema, { indent = true })

    local file, err = io.open(file_path, "w")
    if not file then
        return nil, "Không thể ghi file: " .. tostring(err)
    end

    file:write(json_str)
    file:close()

    SourceRegistry:reloadCustomSources()
    return file_path
end

function DirectImporter:importFromUrl(url, mode_or_key, callback)
    if type(mode_or_key) == "function" then
        callback = mode_or_key
        mode_or_key = "auto"
    end

    local mode = "auto"
    local api_key_override = nil
    if type(mode_or_key) == "string" then
        if mode_or_key == "firecrawl" or mode_or_key == "local" or mode_or_key == "auto" then
            mode = mode_or_key
        else
            api_key_override = mode_or_key
        end
    end

    if not url or url == "" or not url:match("^https?://") then
        if callback then callback(nil, "Đường dẫn URL không hợp lệ (phải bắt đầu bằng http:// hoặc https://)") end
        return
    end

    local base_url = extractHost(url)
    local domain_id = extractDomainId(url)
    local schema, analyze_err, meta
    local method_used = "Super Scraper Engine v3.7.0"

    -- Chế độ 1: Ép dùng Firecrawl API
    if mode == "firecrawl" then
        local api_key = api_key_override or CredentialManager:getFirecrawlKey()
        if not api_key or api_key == "" then
            if callback then callback(nil, "Chưa cấu hình Firecrawl API Key!") end
            return
        end
        local fc_html, fc_err = self:fetchFirecrawl(url, api_key)
        if fc_html then
            schema, analyze_err, meta = self:analyzeHtml(fc_html, base_url, domain_id)
            method_used = "⚡ Firecrawl Cloud API (Ép buộc)"
        else
            if callback then callback(nil, "Firecrawl API cào thất bại: " .. tostring(fc_err)) end
            return
        end
    else
        -- Chế độ Auto hoặc Local: Thử lấy HTML trực tiếp bằng HTTP client của KOReader
        local html, fetch_err = Http:get(url, {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        })

        if html then
            schema, analyze_err, meta = self:analyzeHtml(html, base_url, domain_id)
            if schema then
                method_used = "🚀 Super Scraper Direct HTML (Trực tiếp)"
            end
        end

        -- Nếu Bước 1 thất bại và ở chế độ Auto -> Thử Firecrawl Fallback
        if not schema and mode == "auto" then
            Debug.write("[DirectImporter] Local Heuristic failed (" .. tostring(fetch_err or analyze_err) .. "). Attempting Firecrawl API...")
            local api_key = api_key_override or CredentialManager:getFirecrawlKey()
            if api_key and api_key ~= "" then
                local fc_html, fc_err = self:fetchFirecrawl(url, api_key)
                if fc_html then
                    schema, analyze_err, meta = self:analyzeHtml(fc_html, base_url, domain_id)
                    if schema then
                        method_used = "⚡ Firecrawl Cloud API (Tự động Fallback)"
                    end
                else
                    if callback then callback(nil, "Phân tích thất bại: " .. tostring(fc_err or analyze_err)) end
                    return
                end
            else
                if callback then callback(nil, "Phân tích thất bại và chưa cấu hình Firecrawl API Key: " .. tostring(fetch_err or analyze_err)) end
                return
            end
        end
    end

    if not schema then
        if callback then callback(nil, "Không thể tạo quy tắc nguồn từ URL này: " .. tostring(analyze_err)) end
        return
    end

    schema.matched_template = method_used
    local path, save_err = self:saveSchema(schema)
    if not path then
        if callback then callback(nil, "Lỗi lưu file nguồn: " .. tostring(save_err)) end
        return
    end

    if callback then callback(schema, nil, meta) end
end

return DirectImporter
