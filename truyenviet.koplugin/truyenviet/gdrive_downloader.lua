local Http = require("truyenviet/http_client")
local Debug = require("truyenviet/debugger")
local Storage = require("truyenviet/storage")
local Util = require("truyenviet/helpers")

local GDriveDownloader = {
    SUPPORTED_EXTENSIONS = {
        epub = true,
        cbz = true,
        cbr = true,
        mobi = true,
        pdf = true,
        azw3 = true,
        azw = true,
        fb2 = true,
        txt = true,
        prc = true,
        zip = true,
        rar = true,
    },
}

--- Kiểm tra phần mở rộng file có phải là định dạng ebook được hỗ trợ hay không
function GDriveDownloader:isSupportedExtension(ext)
    if not ext then return false end
    local clean_ext = ext:lower():gsub("^%.", "")
    return self.SUPPORTED_EXTENSIONS[clean_ext] == true
end

--- Trích xuất Google Drive File ID từ nhiều dạng liên kết khác nhau hoặc chuỗi ID thô
function GDriveDownloader:extractFileId(input)
    if not input or type(input) ~= "string" then return nil end
    local trimmed = Util.trim(input)
    if trimmed == "" then return nil end

    -- 1. Dạng /file/d/{ID}
    local id = trimmed:match("/file/d/([%w%-_]+)")
    if id then return id end

    -- 2. Dạng ?id={ID} hoặc &id={ID}
    id = trimmed:match("[?&]id=([%w%-_]+)")
    if id then return id end

    -- 3. Dạng /open?id={ID}
    id = trimmed:match("/open%?id=([%w%-_]+)")
    if id then return id end

    -- 4. Dạng /document/d/{ID} hoặc /spreadsheets/d/{ID} hoặc /presentation/d/{ID}
    id = trimmed:match("/d/([%w%-_]+)")
    if id then return id end

    -- 5. Dạng /uc?id={ID}
    id = trimmed:match("/uc%?id=([%w%-_]+)")
    if id then return id end

    -- 6. Chuỗi ID thô trực tiếp (Google Drive ID thường có độ dài từ 25-45 ký tự)
    if trimmed:match("^[%w%-_]+$") and #trimmed >= 20 and not trimmed:find("%.") then
        return trimmed
    end

    return nil
end

--- Bóc tách tên file từ Content-Disposition header hoặc chuỗi fallback
local function parseContentDispositionFilename(header_val)
    if not header_val then return nil end
    -- filename*=UTF-8''encoded_name
    local encoded = header_val:match("filename%*%s*=%s*UTF%-8''([^;%s]+)")
    if encoded then
        local unescaped = encoded:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
        if unescaped and #unescaped > 0 then
            return unescaped
        end
    end

    -- filename="quoted_name"
    local quoted = header_val:match('filename%s*=%s*"([^"]+)"')
    if quoted and #quoted > 0 then
        return quoted
    end

    -- filename=simple_name
    local simple = header_val:match('filename%s*=%s*([^;%s]+)')
    if simple and #simple > 0 then
        return simple:gsub('^["\']', ''):gsub('["\']$', '')
    end

    return nil
end

--- Tự động phát hiện extension dựa vào Magic Bytes
function GDriveDownloader:detectExtensionFromMagicBytes(content)
    if not content or #content < 4 then return nil end
    local head = content:sub(1, 8)
    if head:sub(1, 4) == "%PDF" then
        return "pdf"
    elseif head:sub(1, 4) == "PK\3\4" then
        -- Có thể là EPUB, CBZ hoặc ZIP
        if content:find("application/epub+zip", 1, true) then
            return "epub"
        end
        return "cbz"
    elseif head:sub(1, 4) == "Rar!" then
        return "cbr"
    end
    -- Kiểm tra MOBI (thường có BOOKMOBI tại offset 60-68)
    if #content >= 68 and content:sub(61, 68) == "BOOKMOBI" then
        return "mobi"
    end
    return nil
end

--- Làm sạch tên file để lưu trữ an toàn trên file system
function GDriveDownloader:sanitizeFilename(name)
    if not name or name == "" then
        return "gdrive_ebook_" .. os.time()
    end
    -- Thay thế các ký tự cấm trong tên file: \ / : * ? " < > |
    local clean = name:gsub('[\\/:*?"<>|]', "_"):gsub("%s+", " ")
    clean = Util.trim(clean)
    if #clean > 120 then
        local ext = clean:match("(%.[%w]+)$") or ""
        clean = clean:sub(1, 110) .. ext
    end
    return clean
end

--- Lấy metadata cơ bản của file Google Drive (tên file, dung lượng, download url)
function GDriveDownloader:fetchMetadata(url_or_id)
    local file_id = self:extractFileId(url_or_id)
    if not file_id then
        return nil, "Không nhận diện được ID file Google Drive từ liên kết đã nhập."
    end

    local preview_url = "https://drive.google.com/file/d/" .. file_id .. "/view"
    Debug.write("[GDrive] Fetching metadata for ID: " .. file_id)

    local html, err, headers = Http:get(preview_url, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    })

    local filename = nil
    if html then
        -- Trích xuất tên từ thẻ <meta property="og:title" content="...">
        filename = html:match('<meta%s+property="og:title"%s+content="([^"]+)"')
            or html:match('<meta%s+name="title"%s+content="([^"]+)"')
            or html:match("<title>([^<]+)%s*-%s*Google%s+Drive</title>")
            or html:match("<title>([^<]+)</title>")

        if filename then
            filename = Util.decodeHtml(Util.trim(filename))
            -- Loại bỏ hậu tố Google Drive nếu còn sót lại
            filename = filename:gsub("%s*-%s*Google%s+Drive$", "")
        end
    end

    if not filename or filename == "" or filename:find("Google Drive") then
        filename = "GoogleDrive_" .. file_id:sub(1, 8)
    end

    local meta = {
        file_id = file_id,
        filename = self:sanitizeFilename(filename),
        preview_url = preview_url,
        direct_url = "https://drive.google.com/uc?export=download&id=" .. file_id,
    }

    return meta
end

--- Tải file Google Drive công khai và lưu vào thư mục đích
--- @param url_or_id string: URL hoặc File ID
--- @param dest_folder_or_path string: Thư mục lưu hoặc đường dẫn file cụ thể
--- @param options table: Tùy chọn (on_progress, preferred_filename)
function GDriveDownloader:download(url_or_id, dest_folder_or_path, options)
    options = options or {}
    local file_id = self:extractFileId(url_or_id)
    if not file_id then
        return nil, "Liên kết Google Drive không hợp lệ hoặc không trích xuất được ID."
    end

    Debug.write(string.format("[GDrive] Starting download process for file_id: %s", file_id))

    local target_dir = dest_folder_or_path or Storage:getGDriveDir()
    local specific_file_path = nil
    if type(target_dir) == "string" and target_dir:match("%.[%w]+$") then
        specific_file_path = target_dir
        target_dir = specific_file_path:match("^(.*)[/\\]") or Storage:getGDriveDir()
    end

    local download_url = "https://drive.google.com/uc?export=download&id=" .. file_id
    local cookies = {}

    local function mergeCookies(res_headers)
        if not res_headers then return end
        local set_cookies = res_headers["set-cookie"] or res_headers["Set-Cookie"]
        if set_cookies then
            if type(set_cookies) == "string" then
                set_cookies = { set_cookies }
            end
            for _, c in ipairs(set_cookies) do
                local name, val = tostring(c):match("^([^=;]+)=([^;]*)")
                if name and val then
                    cookies[name] = val
                end
            end
        end
    end

    local function getCookieHeader()
        local list = {}
        for k, v in pairs(cookies) do
            table.insert(list, k .. "=" .. v)
        end
        return #list > 0 and table.concat(list, "; ") or nil
    end

    -- 1. Request tải lần 1
    local req_headers = {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        ["Accept"] = "*/*",
    }
    local content, err, resp_headers, code = Http:request(
        "GET", download_url, nil, req_headers, { redirect = true }
    )
    mergeCookies(resp_headers)

    if not content then
        return nil, "Lỗi kết nối tải Google Drive: " .. tostring(err)
    end

    local filename = parseContentDispositionFilename(
        resp_headers and (resp_headers["content-disposition"] or resp_headers["Content-Disposition"])
    )

    -- 2. Kiểm tra trang cảnh báo quét virus của Google Drive (đối với file lớn > 25-100MB)
    if content:find("confirm=", 1, true)
            or content:find("download_warning", 1, true)
            or content:find("uc%-download%-link", 1, true)
            or (content:find("<html", 1, true) and content:find("Google Drive")) then
        Debug.write("[GDrive] Virus scan warning page detected. Extracting confirmation token...")

        local confirm_token = content:match('name="confirm"%s+value="([^"]+)"')
            or content:match('confirm=([^"&]+)')
            or content:match("confirm=([^'&]+)")
            or content:match('id="uc%-download%-link"%s+href="[^"]*confirm=([^"&]+)')

        local action_url = content:match('<form[^>]+action="([^"]+)"')
            or content:match('id="uc%-download%-link"%s+href="([^"]+)"')

        local confirmed_url = nil
        if confirm_token then
            confirmed_url = string.format(
                "https://drive.google.com/uc?export=download&id=%s&confirm=%s",
                file_id, confirm_token
            )
        elseif action_url then
            if not action_url:match("^https?://") then
                action_url = "https://drive.google.com" .. action_url
            end
            confirmed_url = action_url:gsub("&amp;", "&")
        end

        if confirmed_url then
            Debug.write("[GDrive] Requesting with confirmation: " .. confirmed_url)
            req_headers["Cookie"] = getCookieHeader()
            local c2, e2, h2, code2 = Http:request(
                "GET", confirmed_url, nil, req_headers, { redirect = true }
            )
            mergeCookies(h2)
            if c2 and #c2 > 500 then
                content = c2
                resp_headers = h2
                local fn2 = parseContentDispositionFilename(
                    h2 and (h2["content-disposition"] or h2["Content-Disposition"])
                )
                if fn2 then filename = fn2 end
            end
        end
    end

    -- 3. Kiểm tra xem nội dung nhận được có phải là file thật hay trang lỗi HTML
    if #content < 1500 and content:find("<html", 1, true) and content:find("error", 1, true) then
        return nil, "Google Drive trả về trang báo lỗi (có thể file bị giới hạn quyền truy cập hoặc quá tải)."
    end

    -- 4. Xác định tên file cuối cùng
    if not filename or filename == "" then
        filename = options.preferred_filename
    end

    if not filename or filename == "" then
        -- Thử lấy metadata từ trang xem trước
        local meta = self:fetchMetadata(file_id)
        if meta and meta.filename then
            filename = meta.filename
        end
    end

    if not filename or filename == "" then
        filename = "GoogleDrive_" .. file_id:sub(1, 8)
    end

    -- Đảm bảo có phần mở rộng file (extension) phù hợp
    local has_ext = filename:match("%.([%w]+)$")
    if not has_ext or not self:isSupportedExtension(has_ext) then
        local detected_ext = self:detectExtensionFromMagicBytes(content)
        if detected_ext then
            filename = filename:gsub("%..*$", "") .. "." .. detected_ext
        else
            -- Mặc định coi là epub nếu không nhận diện được
            filename = filename .. ".epub"
        end
    end

    filename = self:sanitizeFilename(filename)

    -- 5. Ghi file an toàn ra đĩa (dùng file .part để tránh hỏng dữ liệu khi tải dở)
    local final_path = specific_file_path or (target_dir .. "/" .. filename)
    local temp_path = final_path .. ".part"

    local f, open_err = io.open(temp_path, "wb")
    if not f then
        return nil, "Không thể tạo file tạm để lưu: " .. tostring(open_err)
    end

    local written, write_err = f:write(content)
    f:close()

    if not written then
        os.remove(temp_path)
        return nil, "Không thể ghi dữ liệu file: " .. tostring(write_err)
    end

    os.remove(final_path)
    local ok_rename, rename_err = os.rename(temp_path, final_path)
    if not ok_rename then
        -- Fallback copy nếu khác thiết bị lưu trữ
        local fin = io.open(temp_path, "rb")
        local fout = io.open(final_path, "wb")
        if fin and fout then
            fout:write(fin:read("*a"))
            fin:close()
            fout:close()
            os.remove(temp_path)
        else
            if fin then fin:close() end
            if fout then fout:close() end
            os.remove(temp_path)
            return nil, "Không thể di chuyển file hoàn chỉnh: " .. tostring(rename_err)
        end
    end

    Debug.write(string.format("[GDrive] Downloaded successfully: %s (%d bytes)", final_path, #content))
    return final_path, filename, #content
end

--- Tương thích ngược: downloadFile gọi tới download
function GDriveDownloader:downloadFile(url_or_id, dest_folder_or_path, options)
    return self:download(url_or_id, dest_folder_or_path, options)
end

return GDriveDownloader
