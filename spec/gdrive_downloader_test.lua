local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

package.preload["truyenviet/debugger"] = function()
    return { write = function() end }
end

package.preload["socket.url"] = function()
    return {
        escape = function(s) return s end,
        unescape = function(s) return s end,
    }
end

package.preload["util"] = function()
    return {
        htmlEntitiesToUtf8 = function(s) return s end,
        stringLower = function(s) return s:lower() end,
    }
end

package.preload["truyenviet/storage"] = function()
    return {
        getDownloadDir = function()
            return "/tmp"
        end,
    }
end

local mock_requests = {}
local mock_responses = {}
package.preload["truyenviet/http_client"] = function()
    return {
        get = function(self, url, headers)
            return mock_responses[url] or "<html>Mock HTML</html>", nil, {}
        end,
        request = function(self, method, url, body, headers, options)
            table.insert(mock_requests, { method = method, url = url, headers = headers })
            local resp = mock_responses[url] or { content = "PK\3\4...mimetypeapplication/epub+zip", headers = { ["content-disposition"] = 'attachment; filename="Test Book.epub"' } }
            return resp.content, nil, resp.headers, 200
        end,
    }
end

local GDrive = require("truyenviet/gdrive_downloader")
local assertions = 0

local function assertEqual(expected, actual, message)
    assertions = assertions + 1
    if expected ~= actual then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
    end
end

-- 1. Test extractFileId
local id1 = GDrive:extractFileId("https://drive.google.com/file/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/view?usp=sharing")
assertEqual("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms", id1, "Extract ID from view link")

local id2 = GDrive:extractFileId("https://drive.google.com/open?id=1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms")
assertEqual("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms", id2, "Extract ID from open link")

local id3 = GDrive:extractFileId("https://drive.google.com/uc?id=1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms&export=download")
assertEqual("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms", id3, "Extract ID from uc download link")

local id4 = GDrive:extractFileId("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms")
assertEqual("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms", id4, "Extract raw ID string")

-- 2. Test isSupportedExtension
assertEqual(true, GDrive:isSupportedExtension("epub"), "Supports EPUB")
assertEqual(true, GDrive:isSupportedExtension(".cbz"), "Supports CBZ with dot")
assertEqual(true, GDrive:isSupportedExtension("mobi"), "Supports MOBI")
assertEqual(true, GDrive:isSupportedExtension("pdf"), "Supports PDF")
assertEqual(true, GDrive:isSupportedExtension("azw3"), "Supports AZW3")
assertEqual(true, GDrive:isSupportedExtension("fb2"), "Supports FB2")
assertEqual(true, GDrive:isSupportedExtension("txt"), "Supports TXT")
assertEqual(false, GDrive:isSupportedExtension("exe"), "Rejects EXE")

-- 3. Test detectExtensionFromMagicBytes
assertEqual("pdf", GDrive:detectExtensionFromMagicBytes("%PDF-1.5"), "Detects PDF magic bytes")
assertEqual("epub", GDrive:detectExtensionFromMagicBytes("PK\3\4\0\0\0\0mimetypeapplication/epub+zip"), "Detects EPUB magic bytes")
assertEqual("cbr", GDrive:detectExtensionFromMagicBytes("Rar!\26\7\0"), "Detects RAR/CBR magic bytes")

-- 4. Test sanitizeFilename
local clean = GDrive:sanitizeFilename('Sách: "Lập trình & Cuộc sống"/2024?.epub')
assertEqual(true, clean:find(":") == nil, "Sanitizes colons")
assertEqual(true, clean:find('"') == nil, "Sanitizes double quotes")
assertEqual(true, clean:find("%?") == nil, "Sanitizes question marks")

-- 5. Test download execution
local path, name, size = GDrive:download(
    "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms",
    "/tmp/test_download.epub"
)
assertEqual("/tmp/test_download.epub", path, "Downloads to target path")
assertEqual(true, size > 0, "Non-empty file downloaded")
os.remove("/tmp/test_download.epub")

print(string.format("GDrive downloader tests passed: %d assertions", assertions))
