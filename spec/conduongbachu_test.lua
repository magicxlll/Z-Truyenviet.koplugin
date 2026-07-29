local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

local response_by_url = {}
local requested_urls = {}
local Http = {}

function Http:get(url)
    requested_urls[#requested_urls + 1] = url
    return response_by_url[url],
        response_by_url[url] and nil or "missing fixture",
        {},
        response_by_url[url] and 200 or nil
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
                :gsub("&#8211;", "–")
                :gsub("&#8230;", "…")
        end,
        urlEncode = function(value)
            return value:gsub(" ", "+")
        end,
    }
end

local Source = require("truyenviet/sources/conduongbachu")

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

local base = Source.base_url
local story = {
    source_id = Source.id,
    title = "Con Đường Bá Chủ",
    url = base .. "/",
    kind = "text",
}

local category_html = [[
<meta property="og:title" content="Con đường bá chủ - Đọc truyện online">
<meta property="og:image" content="/cover.webp">
<h2 class="entry-title"><a href="https://conduongbachu.com/chuong-3-ket-thuc/">Chương 3: Kết thúc</a></h2>
<a href="https://conduongbachu.com/chapter-truyen/page/2/">2</a>
]]

local index_html = [[
<div class="entry-content single-page">
  <div class="chapter-filter-container">
    <select class="chapter-selector">
      <option value="">-- Chọn Chapter --</option>
      <option value="/chuong-1-hai-so-phan/">Chương 1: Hai số phận</option>
      <option value="/chuong-2-tan-thu-le-bao/">Chương 2: Tân Thủ Lễ Bao</option>
      <option value="/chuong-3-ket-thuc/">Chương 3: Kết thúc</option>
    </select>
  </div>
  <p>Truyện Con đường bá chủ <strong>Chương 3: Kết thúc</strong> tại conduongbachu.com. Nếu muốn tìm chương khác vui lòng nhấp vào ô</p>
  <div class="post-tts-player-wrap">
    <p class="post-tts-headline">NGHE TRUYỆN</p>
    <p class="post-tts-meta">Chương 3</p>
  </div>
  <p>Nội dung đoạn một.</p>
  <p>Nội dung đoạn hai.</p>
</div>
<nav id="nav-below">
  <a rel="prev" href="/chuong-2-tan-thu-le-bao/">Chương trước</a>
  <a rel="next" href="/chuong-3-ket-thuc/">Chương sau</a>
</nav>
]]

response_by_url[base .. "/chapter-truyen/"] = category_html
response_by_url[base .. "/chuong-3-ket-thuc/"] = index_html
response_by_url[base .. "/"] = category_html
response_by_url[base .. "/?s=bá+chủ"] = category_html

local listing = assert(Source:getCompleted(1))
assertEqual(1, #listing.stories, "returns one canonical story")
assertEqual("Con đường bá chủ", listing.stories[1].title, "parses story title")
assertEqual(base .. "/cover.webp", listing.stories[1].cover_url, "parses cover")

local page = assert(Source:getStoryPage(story, 1))
assertEqual(1, page.total_pages, "three fixture chapters fit one page")
assertEqual(3, #page.chapters, "parses every chapter selector option")
assertEqual("Chương 1: Hai số phận", page.chapters[1].title, "sorts chapter 1 first")
assertEqual(3, page.chapters[3].number, "keeps chapter number")

local all = assert(Source:getAllChapters(story))
assertEqual(3, #all, "getAllChapters uses the complete selector index")
assertEqual(
    base .. "/chuong-2-tan-thu-le-bao/",
    all[2].url,
    "keeps chapter URL"
)

local chapter = assert(Source:parseChapter(index_html, all[3]))
assertEqual("Chương 3: Kết thúc", chapter.title, "parses chapter title")
assertEqual(
    true,
    chapter.content:find("Nội dung đoạn một", 1, true) ~= nil,
    "keeps chapter paragraphs"
)
assertEqual(
    false,
    chapter.content:find("NGHE TRUYỆN", 1, true) ~= nil,
    "removes text-to-speech metadata"
)
assertEqual(
    false,
    chapter.content:find("Nếu muốn tìm chương khác", 1, true) ~= nil,
    "removes chapter search introduction"
)
assertEqual(
    base .. "/chuong-2-tan-thu-le-bao/",
    chapter.previous_url,
    "parses previous chapter URL"
)
assertEqual(
    base .. "/chuong-3-ket-thuc/",
    chapter.next_url,
    "parses next chapter URL"
)

local searched = assert(Source:search("bá chủ"))
assertEqual(1, #searched, "search returns canonical story")
assertEqual(
    true,
    #requested_urls >= 4,
    "uses normal WordPress HTML requests"
)

print("ConDuongBachu tests passed: " .. assertions .. " assertions")
