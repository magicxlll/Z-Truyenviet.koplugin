local Http = require("truyenviet/http_client")
local Util = require("truyenviet/helpers")
local Storage = require("truyenviet/storage")
local CredentialManager = require("truyenviet/credential_manager")
local SourceRegistry = require("truyenviet/source_registry")
local Debug = require("truyenviet/debugger")
local ffiutil = require("ffi/util")
local ko_util = require("util")

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

function DirectImporter:analyzeHtml(html, base_url, domain_id)
    if not html or #html < 200 then
        return nil, "Nội dung HTML quá ngắn hoặc rỗng"
    end

    if html:find("Cloudflare", 1, true) or html:find("Just a moment...", 1, true) then
        return nil, "Trang web bị Cloudflare bảo vệ"
    end

    -- Khởi tạo Schema chuẩn tương thích akaytruyen
    local schema = {
        id = "auto_" .. domain_id,
        name = base_url:match("https?://([^/]+)") or domain_id,
        kind = "text",
        base_url = base_url,
        headers = {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
            ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ["Referer"] = base_url .. "/",
        },
        matched_template = "Direct Importer Auto-Detected",
        search = {
            path = "/tim-kiem/?tukhoa={query}",
            story_block_pattern = "<h3[^>]*>([%s%S]-)</h3>",
            title_pattern = "title=[\"']([^\"']+)[\"']",
            url_pattern = "href=[\"']([^\"']+)[\"']",
            cover_pattern = "src=[\"']([^\"']+)[\"']",
        },
        story_details = {
            description_pattern = "<div[^>]-class=[\"'][^\"']*desc[^\"']*[\"'][^>]*>([%s%S]-)</div>",
            author_pattern = "author",
            status_pattern = "status",
        },
        story_page = {
            chapter_item_pattern = "<a[^>]+href=[\"']([^\"']*/chuong%-[^\"']*)[\"'][^>]*>([%s%S]-)</a>",
            total_pages_pattern = "trang%-(%d+)",
        },
        chapter = {
            title_pattern = "<h[12][^>]*>([%s%S]-)</h[12]>",
            content_pattern = "<div[^>]-id=[\"']chapter%-c[\"'][^>]*>([%s%S]-)</div>",
            prev_url_pattern = "prev",
            next_url_pattern = "next",
        },
    }

    -- Tùy chỉnh bóc tách mẫu tìm kiếm
    if html:find("/?s=", 1, true) then
        schema.search.path = "/?s={query}"
    elseif html:find("/search?q=", 1, true) then
        schema.search.path = "/search?q={query}"
    end

    -- Tùy chỉnh bóc tách nội dung chương
    if html:find("chapter%-content") then
        schema.chapter.content_pattern = "<div[^>]-class=[\"'][^\"']*chapter%-content[^\"']*[\"'][^>]*>(.+)</div>"
    elseif html:find("reading%-content") then
        schema.chapter.content_pattern = "<div[^>]-class=[\"'][^\"']*reading%-content[^\"']*[\"'][^>]*>(.+)</div>"
    elseif html:find("cha%-content") then
        schema.chapter.content_pattern = "<div[^>]-class=[\"'][^\"']*cha%-content[^\"']*[\"'][^>]*>(.+)</div>"
    elseif html:find("chapter%-c") then
        schema.chapter.content_pattern = "<div[^>]-id=[\"']chapter%-c[\"'][^>]*>(.+)</div>"
    else
        schema.chapter.content_pattern = "<div[^>]-class=[\"'][^\"']*chapter%-content[^\"']*[\"'][^>]*>(.+)</div>"
    end

    -- Tùy chỉnh mẫu danh sách chương
    if html:find('/chuong-', 1, true) then
        schema.story_page.chapter_item_pattern = "<a[^>]+href=[\"']([^\"']*/chuong%-[^\"']*)[\"'][^>]*>([%s%S]-)</a>"
    elseif html:find('/chapter-', 1, true) then
        schema.story_page.chapter_item_pattern = "<a[^>]+href=[\"']([^\"']*/chapter%-[^\"']*)[\"'][^>]*>([%s%S]-)</a>"
    end

    return schema
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

    -- Decode JSON response
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
    local schema, analyze_err
    local method_used = "Local Heuristic Engine"

    -- Chế độ 1: Ép dùng Firecrawl API
    if mode == "firecrawl" then
        local api_key = api_key_override or CredentialManager:getFirecrawlKey()
        if not api_key or api_key == "" then
            if callback then callback(nil, "Chưa cấu hình Firecrawl API Key!") end
            return
        end
        local fc_html, fc_err = self:fetchFirecrawl(url, api_key)
        if fc_html then
            schema, analyze_err = self:analyzeHtml(fc_html, base_url, domain_id)
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
            schema, analyze_err = self:analyzeHtml(html, base_url, domain_id)
            if schema then
                method_used = "🚀 Local Direct HTML (Trực tiếp)"
            end
        end

        -- Nếu Bước 1 thất bại và ở chế độ Auto -> Thử Firecrawl Fallback
        if not schema and mode == "auto" then
            Debug.write("[DirectImporter] Local Heuristic failed (" .. tostring(fetch_err or analyze_err) .. "). Attempting Firecrawl API...")
            local api_key = api_key_override or CredentialManager:getFirecrawlKey()
            if api_key and api_key ~= "" then
                local fc_html, fc_err = self:fetchFirecrawl(url, api_key)
                if fc_html then
                    schema, analyze_err = self:analyzeHtml(fc_html, base_url, domain_id)
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

    if callback then callback(schema, nil) end
end

return DirectImporter
