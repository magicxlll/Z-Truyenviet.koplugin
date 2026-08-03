local Util = require("truyenviet/helpers")

local SearchService = {}

function SearchService:search(query, sources)
    query = Util.trim(query or "")
    local results = {}
    local errors = {}
    local seen = {}
    local unaccented_query = Util.removeAccents(query)
    if query == "" then
        return results, { "Từ khóa tìm kiếm không được để trống" }
    end

    for source_index, source in ipairs(sources) do
        if type(source.search) == "function" then
            local ok, stories, err = pcall(source.search, source, query)
            
            -- Nếu tìm theo từ có dấu không ra kết quả, thử lại với từ không dấu
            if ok and type(stories) == "table" and #stories == 0
                    and unaccented_query ~= query then
                local ok2, stories2, err2 = pcall(source.search, source, unaccented_query)
                if ok2 and type(stories2) == "table" and #stories2 > 0 then
                    ok, stories, err = ok2, stories2, err2
                end
            end

            if not ok then
                table.insert(
                    errors,
                    tostring(source.name or source.id or "Nguồn")
                        .. ": " .. tostring(stories)
                )
            elseif type(stories) ~= "table" then
                local source_error = err
                if not source_error and type(stories) == "string" then
                    source_error = stories
                end
                table.insert(
                    errors,
                    tostring(source.name or source.id or "Nguồn")
                        .. ": " .. tostring(source_error or "Lỗi không xác định")
                )
            else
                for result_index, story in ipairs(stories) do
                    if type(story) == "table"
                            and type(story.source_id) == "string"
                            and story.source_id ~= ""
                            and type(story.url) == "string"
                            and story.url ~= ""
                            and type(story.title) == "string"
                            and story.title ~= "" then
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
