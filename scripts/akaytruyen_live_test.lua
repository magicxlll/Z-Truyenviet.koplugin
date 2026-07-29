-- Desktop live smoke/benchmark for the AkayTruyen source.
-- Requires: luajit, curl, jq.

local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

local request_count = 0
local transferred_bytes = 0

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function fetch(url)
    request_count = request_count + 1
    local command = table.concat({
        "curl --fail --silent --show-error --location --max-time 60",
        "-H 'Accept: text/html,application/xhtml+xml,application/json'",
        "-H 'User-Agent: Mozilla/5.0 KOReader-TruyenViet-Live-Test'",
        shellQuote(url),
    }, " ")
    local handle = assert(io.popen(command))
    local content = handle:read("*a")
    local ok = handle:close()
    if not ok or content == "" then
        return nil, "curl không tải được " .. url
    end
    transferred_bytes = transferred_bytes + #content
    return content
end

local Http = {}

function Http:get(url)
    local raw, err = fetch(url)
    if not raw then return nil, err end
    return raw, nil, {}, 200
end

function Http:request()
    return nil, "POST không được dùng trong live smoke test"
end

function Http:requestAsync(method, url)
    if method ~= "GET" then return nil, "chỉ hỗ trợ GET" end
    return self:get(url)
end

package.preload["truyenviet/http_client"] = function()
    return Http
end

package.preload["socket.url"] = function()
    return {
        absolute = function(base, href)
            if href:match("^https?://") then return href end
            return base:gsub("/+$", "") .. "/" .. href:gsub("^/+", "")
        end,
    }
end

package.preload["util"] = function()
    return {
        htmlEntitiesToUtf8 = function(value)
            return tostring(value or "")
                :gsub("&amp;", "&")
                :gsub("&quot;", '"')
                :gsub("&#39;", "'")
                :gsub("&lt;", "<")
                :gsub("&gt;", ">")
        end,
        urlEncode = function(value)
            return tostring(value):gsub("([^%w%-_%.~])", function(character)
                return string.format("%%%02X", character:byte())
            end)
        end,
        stringLower = string.lower,
        sanitizeFilename = function(value) return value end,
    }
end

-- The endpoint response is a JSON object containing an HTML string. Decode it
-- with jq in-memory through a second process so this harness needs no Lua rock.
package.preload["json"] = function()
    return {
        decode = function(raw)
            local command = "printf %s "
                .. shellQuote(raw)
                .. " | jq -r '.html'"
            local handle = assert(io.popen(command))
            local html = handle:read("*a")
            local ok = handle:close()
            if not ok or html == "" or html == "null\n" then
                error("JSON endpoint không có field html")
            end
            return { html = html }
        end,
    }
end

local Source = require("truyenviet/sources/akaytruyen")

local function countCovers(stories)
    local count = 0
    for _, story in ipairs(stories or {}) do
        if story.cover_url and story.cover_url ~= "" then count = count + 1 end
    end
    return count
end

local started_at = os.time()
local updating = assert(Source:getUpdating(1))
local hot = assert(Source:getHot(1))
local completed = assert(Source:getCompleted(1))
local home_requests = request_count

assert(#hot.stories >= 20, "Hot trả quá ít truyện")
assert(#updating.stories >= 20, "Đang ra trả quá ít truyện")
assert(#completed.stories >= 1, "Hoàn thành không có truyện")
assert(
    countCovers(updating.stories) == #updating.stories,
    "Đang ra vẫn còn truyện thiếu cover"
)
assert(
    countCovers(completed.stories) == #completed.stories,
    "Hoàn thành vẫn còn truyện thiếu cover"
)
assert(home_requests == 1, "Ba tab phải dùng chung đúng một homepage request")

local search_results = assert(Source:search("Chung Cực Truyền Kỳ"))
local found_target = false
for _, result in ipairs(search_results) do
    if result.url == Source.base_url .. "/truyen/chung-cuc-truyen-ky" then
        found_target = true
        break
    end
end
assert(found_target, "Tìm kiếm không trả đúng Chung Cực Truyền Kỳ")

assert(#hot.genres > 0, "Homepage không parse được chủ đề")
local genre_listing = assert(Source:getGenre(hot.genres[1], 1))
assert(#genre_listing.stories > 0, "Trang chủ đề không trả truyện")
assert(
    countCovers(genre_listing.stories) > 0,
    "Trang chủ đề không parse được cover"
)

local story = {
    source_id = Source.id,
    kind = Source.kind,
    title = "Chung Cực Truyền Kỳ",
    url = Source.base_url .. "/truyen/chung-cuc-truyen-ky",
}
local first_page = assert(Source:getStoryPage(story, 1))
assert(#first_page.chapters > 0, "Endpoint trang 1 không có chương")
assert(first_page.total_pages >= 2, "Không đọc được tổng số trang chương")

local all_chapters = assert(Source:getAllChapters(story))
local seen = {}
for _, chapter in ipairs(all_chapters) do
    assert(not seen[chapter.url], "Danh sách toàn bộ chương bị trùng URL")
    seen[chapter.url] = true
end
assert(#all_chapters >= 300, "Danh sách toàn bộ chương bị thiếu")

local latest = assert(Source:getChapter(all_chapters[1]))
assert(#latest.content > 500, "Nội dung chương mới quá ngắn")
local async_latest = assert(Source:getChapterAsync(all_chapters[1]))
assert(#async_latest.content > 500, "Nội dung chương async quá ngắn")

print(string.format(
    "Akay live passed: hot=%d/%d covers, updating=%d/%d covers, "
        .. "completed=%d/%d covers, search=%d, genre=%d/%d covers, "
        .. "pages=%d, chapters=%d, "
        .. "chapter_chars=%d, requests=%d, bytes=%d, elapsed=%ds",
    countCovers(hot.stories),
    #hot.stories,
    countCovers(updating.stories),
    #updating.stories,
    countCovers(completed.stories),
    #completed.stories,
    #search_results,
    countCovers(genre_listing.stories),
    #genre_listing.stories,
    first_page.total_pages,
    #all_chapters,
    #latest.content,
    request_count,
    transferred_bytes,
    os.time() - started_at
))
