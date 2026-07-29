local root = "."
package.path = table.concat({
    root .. "/truyenviet.koplugin/?.lua",
    root .. "/truyenviet.koplugin/?/init.lua",
    package.path,
}, ";")

local Order = require("truyenviet/chapter_order")
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

local ascending_source = {}
local descending_source = {
    reversed_chapters = true,
}

assertEqual(
    1,
    Order.targetPage(ascending_source, 7, "asc"),
    "A-Z starts at the first server page for ascending sources"
)
assertEqual(
    7,
    Order.targetPage(ascending_source, 7, "desc"),
    "Z-A jumps to the final server page for ascending sources"
)
assertEqual(
    7,
    Order.targetPage(descending_source, 7, "asc"),
    "A-Z jumps to the final server page for descending sources"
)
assertEqual(
    1,
    Order.targetPage(descending_source, 7, "desc"),
    "Z-A jumps to the first server page for descending sources"
)

assertEqual(
    false,
    Order.shouldReverse(ascending_source, "asc"),
    "keeps an ascending page for A-Z"
)
assertEqual(
    true,
    Order.shouldReverse(ascending_source, "desc"),
    "reverses an ascending page for Z-A"
)
assertEqual(
    true,
    Order.shouldReverse(descending_source, "asc"),
    "reverses a descending page for A-Z"
)
assertEqual(
    false,
    Order.shouldReverse(descending_source, "desc"),
    "keeps a descending page for Z-A"
)

assertEqual(
    -1,
    Order.pageStep(descending_source, "asc"),
    "A-Z walks backward through descending server pages"
)
assertEqual(
    1,
    Order.pageStep(descending_source, "desc"),
    "Z-A walks forward through descending server pages"
)
assertEqual(
    2,
    Order.nextChapterIndex("asc", 1),
    "A-Z continues with the next visible chapter"
)
assertEqual(
    1,
    Order.nextChapterIndex("desc", 2),
    "Z-A continues toward the previous visible row"
)
assertEqual(
    6,
    Order.nextReadingPage(descending_source, 7, 7),
    "reading forward crosses to the prior descending server page"
)
assertEqual(
    nil,
    Order.nextReadingPage(descending_source, 1, 7),
    "latest descending page has no later reading page"
)
assertEqual(
    "last",
    Order.nextPageAutoOpen("desc"),
    "descending display opens the last row after crossing a page"
)

local page_data = {
    chapters = {
        { title = "Chương 3" },
        { title = "Chương 2" },
        { title = "Chương 1" },
    },
}
Order.apply(page_data, descending_source, "asc")
assertEqual("asc", page_data.chapter_sort, "stores the selected sort mode")
assertEqual(
    "Chương 1",
    page_data.chapters[1].title,
    "A-Z displays the oldest chapter first"
)

print(string.format("Chapter order tests passed: %d assertions", assertions))
