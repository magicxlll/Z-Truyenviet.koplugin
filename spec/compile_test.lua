local root = arg[1] or "."
local files = {}
local p = io.popen("find " .. root .. "/truyenviet.koplugin -name '*.lua' | sort")
if p then
    for line in p:lines() do
        local rel = line:gsub("^%./", "")
        table.insert(files, rel)
    end
    p:close()
end

for _, path in ipairs(files) do
    local chunk, err = loadfile(path)
    if not chunk then
        error(string.format("%s: %s", path, tostring(err)))
    end
end

print(string.format("Lua compile tests passed: %d files", #files))
