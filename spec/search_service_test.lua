local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

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
        end,
        stringLower = function(value)
            return value:lower()
        end,
    }
end

local SearchService = require("truyenviet/search_service")

local results, errors = SearchService:search("", {
    {
        id = "empty",
        name = "Empty",
        search = function()
            error("must not call source for empty query")
        end,
    },
})
assert(#results == 0, "empty query returned search results")
assert(#errors == 1, "empty query did not return a clear error")

local malformed_results, malformed_errors = SearchService:search("bachu", {
    {
        id = "malformed",
        name = "Malformed",
        search = function()
            return "not a story list"
        end,
    },
    {
        id = "valid",
        name = "Valid",
        search = function()
            return {
                { title = "Thiếu URL", source_id = "valid" },
                {
                    title = "Con Đường Bá Chủ",
                    source_id = "valid",
                    url = "https://example.test/story",
                },
            }
        end,
    },
})
assert(#malformed_results == 1, "malformed source crashed or leaked invalid results")
assert(
    malformed_results[1].title == "Con Đường Bá Chủ",
    "valid search result was lost"
)
assert(#malformed_errors == 1, "malformed source error was not isolated")

local thrown_results, thrown_errors = SearchService:search("bachu", {
    {
        id = "throws",
        name = "Throws",
        search = function()
            error("simulated network/parser failure")
        end,
    },
})
assert(#thrown_results == 0, "throwing source returned results")
assert(
    thrown_errors[1]:find("simulated network/parser failure", 1, true),
    "source exception was not surfaced as an error"
)

print("Search service tests passed")
