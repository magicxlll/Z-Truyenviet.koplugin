local ChapterOrder = {}

local function isDescendingSource(source)
    return source and source.reversed_chapters == true
end

function ChapterOrder.defaultMode(source)
    return isDescendingSource(source) and "desc" or "asc"
end

function ChapterOrder.targetPage(source, total_pages, mode)
    total_pages = math.max(1, tonumber(total_pages) or 1)
    local descending_source = isDescendingSource(source)
    if mode == "desc" then
        return descending_source and 1 or total_pages
    end
    return descending_source and total_pages or 1
end

function ChapterOrder.shouldReverse(source, mode)
    local want_descending = mode == "desc"
    return want_descending ~= isDescendingSource(source)
end

function ChapterOrder.pageStep(source, mode)
    local requested_matches_source =
        (mode == "desc") == isDescendingSource(source)
    return requested_matches_source and 1 or -1
end

function ChapterOrder.nextChapterIndex(mode, current_index)
    return mode == "desc" and current_index - 1 or current_index + 1
end

function ChapterOrder.prevChapterIndex(mode, current_index)
    return mode == "desc" and current_index + 1 or current_index - 1
end

function ChapterOrder.nextReadingPage(source, current_page, total_pages)
    local target = isDescendingSource(source)
        and current_page - 1
        or current_page + 1
    if target < 1 or target > total_pages then
        return nil
    end
    return target
end

function ChapterOrder.prevReadingPage(source, current_page, total_pages)
    local target = isDescendingSource(source)
        and current_page + 1
        or current_page - 1
    if target < 1 or target > total_pages then
        return nil
    end
    return target
end

function ChapterOrder.nextPageAutoOpen(mode)
    return mode == "desc" and "last" or true
end

function ChapterOrder.prevPageAutoOpen(mode)
    return mode == "desc" and true or "last"
end

function ChapterOrder.apply(page_data, source, mode)
    mode = mode == "desc" and "desc" or "asc"
    page_data.chapter_sort = mode
    if ChapterOrder.shouldReverse(source, mode) then
        local reversed = {}
        for index = #page_data.chapters, 1, -1 do
            table.insert(reversed, page_data.chapters[index])
        end
        page_data.chapters = reversed
    end
    return page_data
end

return ChapterOrder
