local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

package.preload["truyenviet/http_client"] = function()
    return {}
end
package.preload["truyenviet/image_utils"] = function()
    return {}
end
package.preload["truyenviet/storage"] = function()
    return {
        settings = {
            readSetting = function()
                return false
            end,
        },
    }
end
package.preload["truyenviet/helpers"] = function()
    return {}
end
package.preload["ffi/util"] = function()
    return {
        joinPath = function(left, right)
            return left .. "/" .. right
        end,
    }
end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function()
            return nil
        end,
    }
end

local CoverCache = require("truyenviet/cover_cache")
local download_calls = 0
CoverCache.download = function(_, story)
    download_calls = download_calls + 1
    if story.id == 3 then
        error("simulated broken cover")
    end
    return "/tmp/" .. story.id .. ".jpg"
end

local stories = {}
for index = 1, 25 do
    stories[index] = {
        id = index,
        source_id = "source",
        cover_url = "https://example.test/" .. index .. ".jpg",
    }
end

local returned = CoverCache:prefetch(stories, {
    get = function()
        return { base_url = "https://example.test" }
    end,
})

assert(returned == stories, "prefetch did not preserve the result list")
assert(
    download_calls == CoverCache.max_prefetch,
    string.format(
        "prefetch must cap cover downloads at %d (got %d)",
        CoverCache.max_prefetch,
        download_calls
    )
)
assert(stories[1].cover_path ~= nil, "valid cover result was not stored")
assert(stories[3].cover_path == nil, "broken cover escaped exception isolation")

print("Cover cache tests passed")
