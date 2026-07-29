require("setupkoenv")
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(
    DataStorage:getDataDir() .. "/settings.reader.lua"
)

local plugin_root = assert(os.getenv("PLUGIN_ROOT"))
package.path = table.concat({
    plugin_root .. "/?.lua",
    plugin_root .. "/?/init.lua",
    package.path,
}, ";")

local Source = require("truyenviet/sources/conduongbachu")
local SearchService = require("truyenviet/search_service")
local CoverCache = require("truyenviet/cover_cache")

local listing = assert(Source:getCompleted(1))
assert(#listing.stories == 4, "expected main story and three spin-offs")
local story = listing.stories[1]

local first_page = assert(Source:getStoryPage(story, 1))
assert(first_page.total_pages == 76, "unexpected live UI page count")
assert(#first_page.chapters == 50, "unexpected live first page size")
assert(first_page.chapters[1].number == 1, "chapter 1 boundary is wrong")
assert(first_page.chapters[50].number == 50, "chapter 50 boundary is wrong")

local last_page = assert(Source:getStoryPage(story, first_page.total_pages))
assert(#last_page.chapters == 2, "last UI page must keep both final posts")
assert(last_page.chapters[#last_page.chapters].number == 3752, "latest boundary is wrong")

local all = assert(Source:getAllChapters(story))
assert(
    #all == 3752,
    string.format(
        "did not preserve all 3752 WordPress chapter posts (got %d)",
        #all
    )
)

local seen_urls = {}
local duplicate_3059 = {}
local has_3399
local has_3509
for _, chapter in ipairs(all) do
    assert(not seen_urls[chapter.url], "duplicate URL leaked into index")
    seen_urls[chapter.url] = true
    if chapter.number == 3059 then
        duplicate_3059[#duplicate_3059 + 1] = chapter.url
    elseif chapter.number == 3399 then
        has_3399 = true
    elseif chapter.number == 3509 then
        has_3509 = true
    end
end
assert(#duplicate_3059 == 2, "distinct chapter 3059 posts were collapsed")
assert(has_3399, "nonstandard /3399-vo-de/ post was lost")
assert(not has_3509, "source fabricated unpublished chapter 3509")

local expected_spin_off_counts = { 15, 16, 6 }
for index = 2, #listing.stories do
    local spin_off = assert(Source:getAllChapters(listing.stories[index]))
    assert(
        #spin_off == expected_spin_off_counts[index - 1],
        "unexpected spin-off chapter count for " .. listing.stories[index].title
    )
end

local first = assert(Source:getChapter(all[1]))
local latest = assert(Source:getChapter(all[#all]))
assert(#first.content > 1000, "chapter 1 content is too short")
assert(#latest.content > 1000, "latest chapter content is too short")
assert(not latest.content:find("NGHE TRUYỆN", 1, true), "TTS block leaked")
assert(
    not latest.content:find("Nếu muốn tìm chương khác", 1, true),
    "chapter-selector introduction leaked"
)

local search_results, search_errors = SearchService:search(
    "Con đường bá chủ",
    { Source }
)
assert(#search_results == 4, "source search did not return all four stories")
assert(#search_errors == 0, "source search returned an error")
assert(
    CoverCache:prefetch(search_results, {
        get = function(_, source_id)
            return source_id == Source.id and Source or nil
        end,
    }) == search_results,
    "cover prefetch did not preserve search results"
)

print(string.format(
    "CDBC LIVE PASS pages=%d posts=%d spin_offs=%d/%d/%d "
        .. "search=%d/%d first_chars=%d latest_chars=%d duplicate_3059=%d",
    first_page.total_pages,
    #all,
    expected_spin_off_counts[1],
    expected_spin_off_counts[2],
    expected_spin_off_counts[3],
    #search_results,
    #search_errors,
    #first.content,
    #latest.content,
    #duplicate_3059
))
