local Storage = require("truyenviet/storage")
local GenericSource = require("truyenviet/generic_source")

local SourceRegistry = {}

local BUILTIN_SOURCES = {
    require("truyenviet/sources/truyenfull"),
    require("truyenviet/sources/truyenqq"),
    require("truyenviet/sources/dualeo"),
    require("truyenviet/sources/truyendich"),
    require("truyenviet/sources/cbunu"),
    require("truyenviet/sources/haccbl"),
    require("truyenviet/sources/giatocvuongtai"),
    require("truyenviet/sources/docln"),
    require("truyenviet/sources/tve4u"),
    require("truyenviet/sources/dilib"),
    require("truyenviet/sources/mizzya"),
    require("truyenviet/sources/metruyenvn"),
    require("truyenviet/sources/aztruyen"),
    require("truyenviet/sources/dualeotruyenfull"),
    require("truyenviet/sources/truyenc"),
    require("truyenviet/sources/akaytruyen"),
    require("truyenviet/sources/storyaclick"),
    require("truyenviet/sources/vireal"),
    require("truyenviet/sources/metruyenchuvn"),
}

local SOURCES = {}
local SOURCES_BY_ID = {}
local DEFAULT_BASE_URLS = {}

local function registerSource(source)
    table.insert(SOURCES, source)
    SOURCES_BY_ID[source.id] = source
    DEFAULT_BASE_URLS[source.id] = source.base_url
end

for _, source in ipairs(BUILTIN_SOURCES) do
    registerSource(source)
end

-- Tải các nguồn tùy chỉnh từ JSON trong thư mục custom_sources
local function loadCustomSources()
    local ok_json, json = pcall(require, "json")
    if not ok_json or not json then return end

    local script_info = debug.getinfo(1, "S")
    local script_path = script_info and script_info.source or ""
    if script_path:sub(1, 1) == "@" then
        script_path = script_path:sub(2)
    end
    local current_dir = script_path:match("(.*[/\\])") or ""
    local custom_dir = current_dir .. "custom_sources"
    local ok_root, root_dir = pcall(function() return Storage:getRootDir() end)
    local data_custom_dir = ok_root and root_dir and (root_dir .. "/custom_sources") or nil

    local dirs_to_check = {
        -- File JSON đóng gói chỉ bổ sung nguồn mới. Không được âm thầm thay
        -- module Lua chuyên biệt có cùng id (AkayTruyen từng bị trường hợp này).
        { path = custom_dir, allow_override = false },
        -- File do người dùng cài trong thư mục dữ liệu vẫn có thể chủ động
        -- ghi đè nguồn tích hợp.
        { path = data_custom_dir, allow_override = true },
    }

    for _, dir_config in ipairs(dirs_to_check) do
        local dir_path = dir_config.path
        if dir_path then
            local ok, lfs_mod = pcall(require, "libs/libkoreader-lfs")
            if not ok then ok, lfs_mod = pcall(require, "lfs") end

            if ok and lfs_mod and pcall(lfs_mod.attributes, dir_path, "mode") then
                for file in lfs_mod.dir(dir_path) do
                    if file:match("%.json$") then
                        local full_path = dir_path .. "/" .. file
                        local f = io.open(full_path, "r")
                        if f then
                            local content = f:read("*a")
                            f:close()
                            local decoded_ok, schema = pcall(json.decode, content)
                            if decoded_ok and schema and schema.id then
                                local custom_src = GenericSource.create(schema)
                                if not SOURCES_BY_ID[schema.id] then
                                    registerSource(custom_src)
                                elseif dir_config.allow_override then
                                    SOURCES_BY_ID[schema.id] = custom_src
                                    for idx, s in ipairs(SOURCES) do
                                        if s.id == schema.id then
                                            SOURCES[idx] = custom_src
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function sortSources()
    local order_list = Storage:getSourceOrder()
    if not order_list or #order_list == 0 then return end

    local order_map = {}
    for idx, id in ipairs(order_list) do
        order_map[id] = idx
    end

    table.sort(SOURCES, function(a, b)
        local order_a = order_map[a.id] or 9999
        local order_b = order_map[b.id] or 9999
        if order_a == order_b then
            return false
        end
        return order_a < order_b
    end)
end

pcall(loadCustomSources)
pcall(sortSources)

local function applyBaseUrl(source)
    source.base_url = Storage:getCustomBaseUrl(source.id)
        or DEFAULT_BASE_URLS[source.id]
    return source
end

function SourceRegistry:get(source_id)
    if not source_id then return nil end
    local source = SOURCES_BY_ID[source_id]
    if source then
        applyBaseUrl(source)
    end
    return source
end

function SourceRegistry:listAll()
    sortSources()
    local result = {}
    for _, source in ipairs(SOURCES) do
        table.insert(result, applyBaseUrl(source))
    end
    return result
end

function SourceRegistry:listEnabled()
    sortSources()
    local result = {}
    for _, source in ipairs(SOURCES) do
        if Storage:isSourceEnabled(source.id) then
            table.insert(result, applyBaseUrl(source))
        end
    end
    return result
end

function SourceRegistry:isEnabled(source_id)
    return SOURCES_BY_ID[source_id] ~= nil and Storage:isSourceEnabled(source_id)
end

function SourceRegistry:setEnabled(source_id, enabled)
    if not SOURCES_BY_ID[source_id] then
        return nil, "Nguồn truyện không tồn tại"
    end
    return Storage:setSourceEnabled(source_id, enabled)
end

function SourceRegistry:saveSourceOrder()
    local order = {}
    for _, s in ipairs(SOURCES) do
        table.insert(order, s.id)
    end
    Storage:setSourceOrder(order)
end

function SourceRegistry:moveUp(source_id)
    for idx, s in ipairs(SOURCES) do
        if s.id == source_id and idx > 1 then
            SOURCES[idx], SOURCES[idx - 1] = SOURCES[idx - 1], SOURCES[idx]
            self:saveSourceOrder()
            return true
        end
    end
    return false
end

function SourceRegistry:moveDown(source_id)
    for idx, s in ipairs(SOURCES) do
        if s.id == source_id and idx < #SOURCES then
            SOURCES[idx], SOURCES[idx + 1] = SOURCES[idx + 1], SOURCES[idx]
            self:saveSourceOrder()
            return true
        end
    end
    return false
end

function SourceRegistry:moveToTop(source_id)
    for idx, s in ipairs(SOURCES) do
        if s.id == source_id then
            table.remove(SOURCES, idx)
            table.insert(SOURCES, 1, s)
            self:saveSourceOrder()
            return true
        end
    end
    return false
end

function SourceRegistry:isCustomSource(source_id)
    local s = SOURCES_BY_ID[source_id]
    if s and s.schema then
        return true
    end
    if source_id and (source_id:find("^auto_") or source_id:find("^custom_")) then
        return true
    end
    return false
end

function SourceRegistry:deleteCustomSource(source_id)
    local ok_root, root_dir = pcall(function() return Storage:getRootDir() end)
    local custom_dir = ok_root and root_dir and (root_dir .. "/custom_sources") or nil

    local script_info = debug.getinfo(1, "S")
    local script_path = script_info and script_info.source or ""
    if script_path:sub(1, 1) == "@" then script_path = script_path:sub(2) end
    local current_dir = script_path:match("(.*[/\\])") or ""
    local plugin_custom_dir = current_dir .. "custom_sources"

    local deleted = false
    local files_to_delete = {
        custom_dir and (custom_dir .. "/" .. source_id .. ".json"),
        plugin_custom_dir and (plugin_custom_dir .. "/" .. source_id .. ".json"),
    }

    for _, path in ipairs(files_to_delete) do
        if path then
            local f = io.open(path, "r")
            if f then
                f:close()
                os.remove(path)
                deleted = true
            end
        end
    end

    if deleted or SOURCES_BY_ID[source_id] then
        SOURCES_BY_ID[source_id] = nil
        for idx, s in ipairs(SOURCES) do
            if s.id == source_id then
                table.remove(SOURCES, idx)
                break
            end
        end
        self:saveSourceOrder()
        self:reloadCustomSources()
        return true
    end
    return nil, "Không tìm thấy file nguồn tùy chỉnh để xóa"
end

function SourceRegistry:reloadCustomSources()
    pcall(loadCustomSources)
    pcall(sortSources)
end

function SourceRegistry:enableAll()
    for _, s in ipairs(SOURCES) do
        Storage:setSourceEnabled(s.id, true)
    end
end

function SourceRegistry:disableAll()
    for _, s in ipairs(SOURCES) do
        Storage:setSourceEnabled(s.id, false)
    end
end

function SourceRegistry:resetAllDomains()
    for _, s in ipairs(SOURCES) do
        Storage:setCustomBaseUrl(s.id, nil)
    end
end

function SourceRegistry:getSourceInfo(source_id)
    local s = SOURCES_BY_ID[source_id]
    if not s then return "Không tìm thấy nguồn" end
    local custom_domain = Storage:getCustomBaseUrl(s.id)
    local default_domain = DEFAULT_BASE_URLS[s.id] or s.base_url or ""
    local is_custom = self:isCustomSource(s.id)
    local status = Storage:isSourceEnabled(s.id) and "Đang hoạt động" or "Đã tắt"

    local info = {
        "ID: " .. s.id,
        "Tên nguồn: " .. s.name,
        "Loại nguồn: " .. (s.kind == "comic" and "Truyện tranh (CBZ)" or (s.kind == "ebook" and "Ebook" or "Truyện chữ (HTML)")),
        "Trạng thái: " .. status,
        "Tên miền mặc định: " .. default_domain,
        "Tên miền hiện tại: " .. (custom_domain or default_domain),
        "Kiểu nguồn: " .. (is_custom and "Nguồn tùy chỉnh (JSON)" or "Nguồn tích hợp sẵn"),
    }
    return table.concat(info, "\n")
end

return SourceRegistry

