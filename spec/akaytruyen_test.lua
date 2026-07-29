local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

local requested_urls = {}
local response_by_url = {}
local headers_by_url = {}
local last_headers = {}
local last_post
local Http = {}

function Http:get(url, headers)
    requested_urls[#requested_urls + 1] = url
    last_headers = headers or {}
    return response_by_url[url],
        response_by_url[url] and nil or "missing fixture",
        headers_by_url[url],
        response_by_url[url] and 200 or nil
end

function Http:request(method, url, body, headers, options)
    last_post = {
        method = method,
        url = url,
        body = body,
        headers = headers,
        options = options,
    }
    return nil, "redirect", {
        location = "/",
        ["set-cookie"] = "akay_session=session123; Path=/; HttpOnly",
    }, 302
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

local function clearRequests()
    for index = #requested_urls, 1, -1 do
        table.remove(requested_urls, index)
    end
end

local story = {
    title = "Chung Cực Truyền Kỳ",
    url = "https://akaytruyen.com/truyen/chung-cuc-truyen-ky",
}

local home_page = [[
    <div class="section-stories-hot mb-3">
      <a href="https://akaytruyen.com/truyen/truyen-hot-demo">
        <h3 class="story-name">Nhiệt Demo</h3>
      </a>
    </div>
    <div class="section-stories-new mb-3">
      <h3 class="title-text-story">
        <a href="https://akaytruyen.com/truyen/truyen-dang-ra-demo"
           title="Đang Ra Demo">Đang Ra Demo</a>
      </h3>
    </div>
    <div class="section-stories-full mb-3">
      <a href="https://akaytruyen.com/truyen/truyen-full-demo">
        <img src="/covers/full.jpg" alt="Truyện Full Demo">
      </a>
      <a class="story-name"
         href="https://akaytruyen.com/truyen/truyen-full-demo">
        Hoàn Demo
      </a>
    </div>
    <div id="id_feedback_button"></div>
]]

response_by_url[AkayTruyen.base_url] = home_page
response_by_url[AkayTruyen.base_url .. "/"] = home_page

local updating_listing = assert(AkayTruyen:getUpdating(1))
assertEqual(1, #updating_listing.stories, "loads updating stories from homepage")
assertEqual(
    "Đang Ra Demo",
    updating_listing.stories[1].title,
    "isolates the updating section"
)
assertEqual(1, updating_listing.total_pages, "updating section has one page")

local hot_listing = assert(AkayTruyen:getHot(1))
assertEqual(1, #hot_listing.stories, "loads hot stories from homepage")
assertEqual(
    "Nhiệt Demo",
    hot_listing.stories[1].title,
    "isolates the hot section"
)

local completed_listing = assert(AkayTruyen:getCompleted(1))
assertEqual(1, #completed_listing.stories, "loads completed stories from homepage")
assertEqual(
    "Hoàn Demo",
    completed_listing.stories[1].title,
    "isolates the completed section"
)

clearRequests()

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
    nil,
    last_headers["X-Requested-With"],
    "does not send AJAX header to chapter pages"
)
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

local vip_html = [[
    <h1>Chương 1: SỐ PHẬN!</h1>
    <div id="chapter-content">
      <div class="access-denied-container">
        <h4>Truy cập bị hạn chế</h4>
        <p>Chương này dành cho tài khoản VIP trở lên.</p>
        <a href="/login">Đăng nhập</a>
      </div>
    </div>
]]
local public_chapter_with_lock_css = [[
    <style>.access-denied-container { display: flex; }</style>
    <h1>Chương công khai</h1>
    <div id="chapter-content"><p>Nội dung công khai hợp lệ.</p></div>
]]
local public_result = assert(AkayTruyen:parseChapter(
    public_chapter_with_lock_css,
    {
        title = "Chương công khai",
        url = "https://akaytruyen.com/demo/chuong-cong-khai",
    }
))
assertEqual(
    true,
    public_result.content:find("Nội dung công khai", 1, true) ~= nil,
    "does not mistake shared VIP CSS for an actual lock screen"
)

local vip_result, vip_err = AkayTruyen:parseChapter(vip_html, {
    title = "Chương 1: SỐ PHẬN!",
    url = "https://akaytruyen.com/ngoai-truyen-chua-te-chi-lo/chuong-1-so-phan",
})
assertEqual(nil, vip_result, "does not save the VIP lock screen as chapter content")
assertEqual(
    true,
    vip_err and vip_err:find("VIP", 1, true) ~= nil,
    "explains that a valid VIP account is required"
)

response_by_url[AkayTruyen.base_url .. "/login"] = [[
    <form action="/login" method="post">
      <input type="hidden" name="_token" value="csrf123">
    </form>
]]
headers_by_url[AkayTruyen.base_url .. "/login"] = {
    ["set-cookie"] = "XSRF-TOKEN=token123; Path=/",
}
response_by_url[AkayTruyen.base_url .. "/"] = [[
    <form action="https://akaytruyen.com/logout" method="post"></form>
]]

local login_ok, login_err = AkayTruyen:login(
    "vip@example.com",
    "secret"
)
assertEqual(true, login_ok, "accepts a verified Akay login session")
assertEqual(nil, login_err, "does not return an error after login")
assertEqual("POST", last_post.method, "submits the Akay login form")
assertEqual(
    true,
    last_post.body:find("email=vip@example.com", 1, true) ~= nil,
    "submits the account email"
)
assertEqual(
    true,
    last_post.headers.Cookie
        and last_post.headers.Cookie:find("XSRF-TOKEN=token123", 1, true)
            ~= nil,
    "carries the CSRF session cookie into login"
)

print(string.format("AkayTruyen tests passed: %d assertions", assertions))
