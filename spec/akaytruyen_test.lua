local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

local requested_urls = {}
local response_by_url = {}
local Http = {}

function Http:get(url, headers)
    requested_urls[#requested_urls + 1] = url
    if not headers or headers["X-Requested-With"] ~= "XMLHttpRequest" then
        return nil, "missing X-Requested-With"
    end
    return response_by_url[url], response_by_url[url] and nil or "missing fixture"
end

package.preload["truyenviet/http_client"] = function()
    return Http
end

package.preload["socket.url"] = function()
    return {
        absolute = function(base, href)
            if href:match("^https?://") then
                return href
            end
            return base:gsub("/+$", "") .. "/" .. href:gsub("^/+", "")
        end,
    }
end

package.preload["util"] = function()
    return {
        htmlEntitiesToUtf8 = function(value)
            return value
                :gsub("&amp;", "&")
                :gsub("&quot;", '"')
                :gsub("&#39;", "'")
        end,
        urlEncode = function(value)
            return value:gsub(" ", "%%20")
        end,
    }
end

local AkayTruyen = require("truyenviet/sources/akaytruyen")

local assertions = 0

local function assertEqual(expected, actual, message)
    assertions = assertions + 1
    if expected ~= actual then
        error(string.format(
            "%s: expected %s, got %s",
            message,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local story = {
    title = "Chung Cực Truyền Kỳ",
    url = "https://akaytruyen.com/truyen/chung-cuc-truyen-ky",
}

local page_1 = [[
    <a class="chapter-link-mobile"
       href="https://akaytruyen.com/chung-cuc-truyen-ky/chuong-323-thi-giai-su">
      <div class="chapter-number">Chương 323</div>
      <div class="chapter-title">THI GIẢI SƯ!</div>
    </a>
    <a class="chapter-link-mobile"
       href="https://akaytruyen.com/chung-cuc-truyen-ky/21-chinh-hay-ta">
      <div class="chapter-number">Chương 21</div>
      <div class="chapter-title">CHÍNH HAY TÀ?</div>
    </a>
    <a class="story-action"
       href="https://akaytruyen.com/chung-cuc-truyen-ky/gioi-thieu-truyen">
      Giới thiệu truyện
    </a>
    <input class="jump-input input-paginate" min="1" max="2">
]]

local page_2 = [[
    <a class="chapter-link-mobile"
       href="https://akaytruyen.com/chung-cuc-truyen-ky/khai-menh-nghich-thien">
      <div class="chapter-number">Chương 1</div>
      <div class="chapter-title">KHAI MỆNH NGHỊCH THIÊN</div>
    </a>
    <a class="new-badge"
       href="https://akaytruyen.com/chung-cuc-truyen-ky/chuong-323-thi-giai-su">
      New
    </a>
]]

local first_page = AkayTruyen:parseStoryPage(page_1, story, 1)
assertEqual(2, #first_page.chapters, "filters non-chapter story links")
assertEqual(2, first_page.total_pages, "reads total chapter pages")
assertEqual(
    "https://akaytruyen.com/chung-cuc-truyen-ky/21-chinh-hay-ta",
    first_page.chapters[2].url,
    "accepts numbered legacy chapter URL"
)

response_by_url[story.url] = page_1
response_by_url[story.url .. "?page=2"] = page_2
local all_chapters = assert(AkayTruyen:getAllChapters(story))

assertEqual(3, #all_chapters, "loads chapters from every page")
assertEqual(2, #requested_urls, "requests every chapter page")
assertEqual(
    "https://akaytruyen.com/chung-cuc-truyen-ky/khai-menh-nghich-thien",
    all_chapters[3].url,
    "accepts legacy chapter URL without a number"
)

response_by_url[story.url .. "?page=2"] = nil
local partial_result, partial_err = AkayTruyen:getAllChapters(story)
assertEqual(nil, partial_result, "rejects a partial all-chapters result")
assertEqual(
    true,
    partial_err and partial_err:find("trang 2/2", 1, true) ~= nil,
    "reports the failed chapter page"
)

response_by_url[story.url .. "?page=2"] = page_1
local duplicate_result, duplicate_err = AkayTruyen:getAllChapters(story)
assertEqual(nil, duplicate_result, "rejects repeated pagination data")
assertEqual(
    true,
    duplicate_err and duplicate_err:find("dữ liệu trùng", 1, true) ~= nil,
    "reports repeated pagination data"
)

print(string.format("AkayTruyen tests passed: %d assertions", assertions))
