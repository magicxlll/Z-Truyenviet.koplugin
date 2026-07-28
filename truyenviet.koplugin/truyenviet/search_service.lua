local Util = require("truyenviet/helpers")

local SearchService = {}

function SearchService:search(query, sources)
    local results = {}
    local errors = {}
    local seen = {}
    local unaccented_query = Util.removeAccents(query)

    for source_index, source in ipairs(sources) do
        local ok, stories, err = pcall(source.search, source, query)
        
        -- Nếu tìm theo từ có dấu không ra kết quả, thử lại với từ không dấu
        if (not ok or not stories or #stories == 0) and unaccented_query ~= query then
            local ok2, stories2, err2 = pcall(source.search, source, unaccented_query)
            if ok2 and stories2 and #stories2 > 0 then
                ok, stories, err = ok2, stories2, err2
            end
        end

        if not ok then
            table.insert(errors, source.name .. ": " .. tostring(stories))
        elseif not stories then
            table.insert(errors, source.name .. ": " .. tostring(err or "Lỗi không xác định"))
        else
            for result_index, story in ipairs(stories) do
                local key = story.source_id .. "|" .. story.url
                if not seen[key] then
                    seen[key] = true
                    story.source_name = source.name
                    story.search_score = Util.searchScore(
                        query,
                        story.title,
                        result_index + (source_index - 1) * 100
                    )
                    table.insert(results, story)
                end
            end
        end
    end

    table.sort(results, function(left, right)
        if left.search_score ~= right.search_score then
            return left.search_score > right.search_score
        end
        local left_title = Util.normalizeSearch(left.title)
        local right_title = Util.normalizeSearch(right.title)
        if left_title ~= right_title then
            return left_title < right_title
        end
        return left.source_id < right.source_id
    end)

    return results, errors
end

return SearchService
