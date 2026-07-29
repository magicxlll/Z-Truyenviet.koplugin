local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

local responses = {}
local requested_urls = {}
local Http = {}

function Http:get(url)
    requested_urls[#requested_urls + 1] = url
    local response = responses[url]
    if not response then
        return nil, "missing fixture", {}, nil
    end
    return response.body, response.err, response.headers or {}, response.code or 200
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

package.preload["json"] = function()
    return {
        decode = function(raw)
            local posts = {}
            for link, title in raw:gmatch(
                '{"link":"([^"]+)","title":{"rendered":"([^"]*)"}}'
            ) do
                posts[#posts + 1] = {
                    link = link,
                    title = { rendered = title },
                }
            end
            return posts
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

local function assertContains(value, needle, message)
    assertEqual(true, value and value:find(needle, 1, true) ~= nil, message)
end

local base = Source.base_url
local story = {
    source_id = Source.id,
    title = "Con Đường Bá Chủ (Chính Truyện)",
    url = base .. "/",
    kind = "text",
}

local function apiUrl(category, page, order)
    local suffix = order and "&order=asc&orderby=date" or ""
    return base
        .. "/wp-json/wp/v2/posts?categories=" .. category
        .. "&per_page=100&_fields=link,title&page=" .. page
        .. suffix
end

local function postJson(number, url_number)
    url_number = url_number or number
    return string.format(
        '{"link":"%s/chuong-%d-noi-dung/","title":{"rendered":"Chương %d: Nội dung"}}',
        base,
        url_number,
        number
    )
end

local function legacyPostJson(number)
    return string.format(
        '{"link":"%s/%d-vo-de/","title":{"rendered":"%d: VÔ ĐỀ."}}',
        base,
        number,
        number
    )
end

local function pageJson(first, last, duplicate_number)
    local posts = {}
    for number = first, last do
        local rendered_number = number == last and duplicate_number or number
        posts[#posts + 1] = postJson(rendered_number, number)
    end
    return "[" .. table.concat(posts, ",") .. "]"
end

local function setPage(page, body)
    responses[apiUrl(3, page)] = {
        body = body,
        headers = {
            ["x-wp-total"] = "201",
            ["x-wp-totalpages"] = "3",
        },
    }
    responses[apiUrl(3, page, true)] = responses[apiUrl(3, page)]
end

responses[base .. "/"] = {
    body = '<meta name="description" content="Con đường bá chủ">',
}
responses[base .. "/?s=bá+chủ"] = {
    body = "<html></html>",
}
setPage(1, pageJson(1, 100))

local listing = assert(Source:getCompleted(1))
assertEqual(4, #listing.stories, "returns the main story and three spin-offs")
assertEqual(
    "Con Đường Bá Chủ (Chính Truyện)",
    listing.stories[1].title,
    "keeps canonical main story title"
)

-- BUILD-1324 silently stopped at the first failed REST page, cached only the
-- prefix, and reported that partial index as success. This reproduces the
-- user's exact "not all chapters are displayed" symptom.
Source._chapter_index = {}
local partial, partial_err = Source:getAllChapters(story)
assertEqual(nil, partial, "never reports a partial chapter index as success")
assertContains(partial_err, "trang 2", "identifies the failed REST page")

setPage(2, pageJson(101, 200, 199))
setPage(3, "[" .. legacyPostJson(201) .. "]")

local all = assert(Source:getAllChapters(story))
assertEqual(201, #all, "returns every published WordPress chapter post")
assertEqual(1, all[1].number, "sorts the first chapter first")
assertEqual(201, all[#all].number, "sorts the final chapter last")
assertEqual(
    base .. "/201-vo-de/",
    all[#all].url,
    "keeps a numeric legacy slug without the word Chương"
)

local duplicate_count = 0
for _, chapter in ipairs(all) do
    if chapter.number == 199 then
        duplicate_count = duplicate_count + 1
    end
end
assertEqual(
    2,
    duplicate_count,
    "keeps distinct posts that share the same rendered chapter number"
)

Source._chapter_index = {}
local page = assert(Source:getStoryPage(story, 5))
assertEqual(5, page.total_pages, "uses the complete WordPress total")
assertEqual(1, #page.chapters, "last UI page contains the final published post")
assertEqual(201, page.chapters[1].number, "last UI page ends at chapter 201")

local chapter_html = [[
<h1 class="entry-title">Chương 201: Kết thúc</h1>
<div class="entry-content single-page">
  <p>Truyện Con đường bá chủ. Nếu muốn tìm chương khác vui lòng nhấp vào ô</p>
  <p class="post-tts-meta">NGHE TRUYỆN</p>
  <p>Nội dung đoạn một.</p>
  <p>Nội dung đoạn hai.</p>
</div>
<nav id="nav-below">
  <a rel="prev" href="/chuong-200-noi-dung/">Chương trước</a>
</nav>
]]

local chapter = assert(Source:parseChapter(chapter_html, all[#all]))
assertEqual("Chương 201: Kết thúc", chapter.title, "parses chapter title")
assertContains(chapter.content, "Nội dung đoạn một", "keeps chapter paragraphs")
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

local searched = assert(Source:search("bá chủ"))
assertEqual(4, #searched, "search returns all matching Con Đường Bá Chủ stories")
assertEqual(true, #requested_urls > 0, "uses the WordPress source requests")

print("ConDuongBachu tests passed: " .. assertions .. " assertions")
