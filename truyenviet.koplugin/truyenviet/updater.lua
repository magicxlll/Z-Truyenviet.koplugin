local Http = require("truyenviet/http_client")
local Storage = require("truyenviet/storage")
local Version = require("truyenviet/version")
local Debug = require("truyenviet/debugger")
local Util = require("truyenviet/helpers")

local Updater = {
    RAW_VERSION_URL = "https://raw.githubusercontent.com/magicxlll/Z-Truyenviet.koplugin/main/truyenviet.koplugin/truyenviet/version.lua",
    RAW_CHANGELOG_URL = "https://raw.githubusercontent.com/magicxlll/Z-Truyenviet.koplugin/main/CHANGELOG.md",
    RELEASE_API_URL = "https://api.github.com/repos/magicxlll/Z-Truyenviet.koplugin/releases/latest",
    TAGS_API_URL = "https://api.github.com/repos/magicxlll/Z-Truyenviet.koplugin/tags",
    DEFAULT_DOWNLOAD_URL = "https://github.com/magicxlll/Z-Truyenviet.koplugin/raw/main/dist/truyenviet.koplugin.zip",

    _is_checking = false,
    _is_updating = false,
}

--- Phân tích chuỗi phiên bản thành các thành phần số
--- Hỗ trợ: "3.10.0 (BUILD-1370)", "v3.10.0", "3.9.4", "BUILD-1368"
function Updater:parseVersion(str)
    if not str or type(str) ~= "string" then
        return { major = 0, minor = 0, patch = 0, build = 0, raw = "" }
    end

    local clean = str:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^v", "")
    local major, minor, patch = clean:match("(%d+)%.(%d+)%.(%d+)")
    if not major then
        major, minor = clean:match("(%d+)%.(%d+)")
        patch = 0
    end

    local build = clean:match("[bB][uU][iI][lL][dD]%-(%d+)")
        or clean:match("[bB]uild%s*(%d+)")
        or 0

    return {
        major = tonumber(major) or 0,
        minor = tonumber(minor) or 0,
        patch = tonumber(patch) or 0,
        build = tonumber(build) or 0,
        raw = str,
    }
end

--- So sánh xem phiên bản remote có MỚI HƠN phiên bản hiện tại hay không
function Updater:isNewer(remote_str, local_str)
    if not remote_str or remote_str == "" then return false end
    local r = self:parseVersion(remote_str)
    local l = self:parseVersion(local_str or Version)

    if r.major ~= l.major then return r.major > l.major end
    if r.minor ~= l.minor then return r.minor > l.minor end
    if r.patch ~= l.patch then return r.patch > l.patch end
    if r.build > 0 and l.build > 0 and r.build ~= l.build then
        return r.build > l.build
    end

    -- Nếu không bóc tách được số, so sánh chuỗi khác biệt nếu remote có nội dung
    if r.major == 0 and l.major == 0 and r.build == 0 and l.build == 0 then
        return remote_str ~= (local_str or Version)
    end

    return false
end

--- Trích xuất tóm tắt nhật ký thay đổi (Changelog) mới nhất
function Updater:extractChangelogSummary(changelog_text, target_version)
    if not changelog_text or changelog_text == "" then return "" end

    local lines = {}
    local in_target_section = false
    local count = 0

    for line in changelog_text:gmatch("[^\r\n]+") do
        if line:find("^##%s+") then
            if not in_target_section then
                in_target_section = true
            else
                -- Đã sang phiên bản cũ hơn tiếp theo
                break
            end
        elseif in_target_section then
            local trimmed = Util.trim(line)
            if trimmed ~= "" and not trimmed:find("^###") then
                table.insert(lines, trimmed)
                count = count + 1
                if count >= 8 then break end
            end
        end
    end

    if #lines > 0 then
        return "Nội dung cập nhật:\n" .. table.concat(lines, "\n")
    end
    return ""
end

--- Lấy thông tin bản phát hành từ các endpoint GitHub
function Updater:fetchRemoteInfo()
    Debug.write("[OTA] Fetching remote version info...")

    -- 1. Ưu tiên kiểm tra trực tiếp raw version.lua từ nhánh main
    local raw_ver, _, _ = Http:get(self.RAW_VERSION_URL)
    local remote_v = nil
    if raw_ver then
        remote_v = raw_ver:match('return%s*["\']([^"\']+)["\']')
    end

    -- 2. Tải changelog tóm tắt nếu có
    local changelog_summary = ""
    local raw_cl = Http:get(self.RAW_CHANGELOG_URL)
    if raw_cl then
        changelog_summary = self:extractChangelogSummary(raw_cl, remote_v)
    end

    if remote_v and remote_v ~= "" then
        return {
            latest_version = remote_v,
            download_url = self.DEFAULT_DOWNLOAD_URL,
            changelog = changelog_summary,
            source = "raw_github",
        }
    end

    -- 3. Dự phòng qua GitHub Releases API
    local rel_json = Http:get(self.RELEASE_API_URL)
    if rel_json then
        local tag_name = rel_json:match('"tag_name"%s*:%s*"([^"]+)"')
        local asset_url = rel_json:match('"browser_download_url"%s*:%s*"([^"]+%.zip)"')
        local body = rel_json:match('"body"%s*:%s*"([^"]+)"')
        if tag_name then
            return {
                latest_version = tag_name,
                download_url = asset_url or self.DEFAULT_DOWNLOAD_URL,
                changelog = body and body:gsub("\\n", "\n") or changelog_summary,
                source = "github_release",
            }
        end
    end

    -- 4. Dự phòng qua GitHub Tags API
    local tags_json = Http:get(self.TAGS_API_URL)
    if tags_json then
        local tag_name = tags_json:match('"name"%s*:%s*"([^"]+)"')
        if tag_name then
            return {
                latest_version = tag_name,
                download_url = self.DEFAULT_DOWNLOAD_URL,
                changelog = changelog_summary,
                source = "github_tags",
            }
        end
    end

    return nil, "Không thể kết nối máy chủ GitHub hoặc không nhận diện được phiên bản mới."
end

--- Kiểm tra xem có bản cập nhật mới hay không
function Updater:checkForUpdate(callback)
    if self._is_checking then
        if callback then callback(false, nil, "Đang trong tiến trình kiểm tra cập nhật") end
        return
    end

    self._is_checking = true
    local info, err = self:fetchRemoteInfo()
    self._is_checking = false

    if not info then
        if callback then callback(false, nil, err) end
        return false, nil, err
    end

    local current_version = Version
    local has_update = self:isNewer(info.latest_version, current_version)

    if callback then
        callback(has_update, info, nil)
    end
    return has_update, info, nil
end

--- Tải xuống và giải nén cài đặt gói cập nhật zip
function Updater:downloadAndInstall(download_url, callback)
    if self._is_updating then
        if callback then callback(false, "Đang thực hiện cập nhật dở") end
        return false, "Đang thực hiện cập nhật dở"
    end
    self._is_updating = true

    Debug.write("[OTA] Downloading update from: " .. tostring(download_url))
    local body, download_err = Http:get(download_url)
    if not body or #body < 10000 then
        self._is_updating = false
        local msg = download_err or "File cập nhật không hợp lệ hoặc kích thước quá nhỏ (< 10KB)."
        if callback then callback(false, msg) end
        return false, msg
    end

    -- Kiểm tra Magic Bytes ZIP: PK\3\4
    if body:sub(1, 4) ~= "PK\3\4" then
        self._is_updating = false
        local msg = "Nội dung tải về không phải là file zip hợp lệ (có thể là trang lỗi HTML)."
        if callback then callback(false, msg) end
        return false, msg
    end

    local ffiutil = require("ffi/util")
    local DataStorage = require("datastorage")

    local zip_path = ffiutil.joinPath(Storage:getRootDir(), "truyenviet_ota_update.zip")
    local file, open_err = io.open(zip_path, "wb")
    if not file then
        self._is_updating = false
        local msg = "Không thể tạo file tạm để lưu bản cập nhật: " .. tostring(open_err)
        if callback then callback(false, msg) end
        return false, msg
    end

    local written, write_err = file:write(body)
    file:close()

    if not written then
        os.remove(zip_path)
        self._is_updating = false
        local msg = "Không thể ghi dữ liệu bản cập nhật: " .. tostring(write_err)
        if callback then callback(false, msg) end
        return false, msg
    end

    local plugins_dir = ffiutil.joinPath(DataStorage:getDataDir(), "plugins")
    Debug.write(string.format("[OTA] Extracting %s into %s", zip_path, plugins_dir))

    -- Thử giải nén bằng unzip CLI
    local cmd = string.format("unzip -o %q -d %q", zip_path, plugins_dir)
    local status = os.execute(cmd)

    -- Dự phòng thử busybox unzip nếu unzip thất bại
    if status ~= 0 and status ~= true then
        local fallback_cmd = string.format("busybox unzip -o %q -d %q", zip_path, plugins_dir)
        status = os.execute(fallback_cmd)
    end

    os.remove(zip_path)
    self._is_updating = false

    if status ~= 0 and status ~= true then
        local msg = "Không thể giải nén bản cập nhật vào thư mục plugins."
        if callback then callback(false, msg) end
        return false, msg
    end

    Storage:setLastUpdateCheckTime(os.time())
    Debug.write("[OTA] Update extracted successfully!")
    if callback then callback(true, nil) end
    return true, nil
end

--- Khởi động lại KOReader an toàn
function Updater:restartKOReader()
    Debug.write("[OTA] Initiating KOReader restart...")
    local ok_dev, Device = pcall(require, "device")
    if ok_dev and Device and type(Device.restartKOReader) == "function" then
        Device:restartKOReader()
        return
    end

    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    if ok_ui and UIManager and type(UIManager.restartKOReader) == "function" then
        UIManager:restartKOReader()
        return
    end

    -- Exit code 85 là tín hiệu khởi động lại tiêu chuẩn của KOReader
    os.exit(85)
end

--- Hiển thị hộp thoại xác nhận khi có bản cập nhật mới
function Updater:showUpdateDialog(info, on_cancel)
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")

    local current_version = Version
    local latest_version = info.latest_version
    local changelog_text = (info.changelog and info.changelog ~= "")
        and ("\n\n" .. info.changelog) or ""

    local message = string.format(
        "Đã có phiên bản mới: %s\nPhiên bản hiện tại: %s%s\n\nBạn có muốn tải xuống và cập nhật ngay bây giờ không?",
        latest_version, current_version, changelog_text
    )

    local dialog
    dialog = ConfirmBox:new{
        title = "🚀 Bản Cập Nhật Mới - Truyện Việt",
        text = message,
        ok_text = "Cập nhật ngay",
        ok_callback = function()
            self:performUpdateWithUI(info.download_url, latest_version, on_cancel)
        end,
        cancel_text = "Để sau",
        cancel_callback = function()
            if on_cancel then on_cancel() end
        end,
    }
    UIManager:show(dialog)
end

--- Tiến hành cập nhật kèm giao diện tải nạp & thông báo kết quả
function Updater:performUpdateWithUI(download_url, latest_version, on_finish)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local ConfirmBox = require("ui/widget/confirmbox")

    local loading = InfoMessage:new{
        title = "Truyện Việt OTA",
        text = "Đang tải xuống và cài đặt bản cập nhật mới...\n(Vui lòng không tắt máy)",
        dismissable = false,
    }
    UIManager:show(loading)
    UIManager:forceRePaint()

    UIManager:nextTick(function()
        local success, err = self:downloadAndInstall(download_url)
        UIManager:close(loading)

        if success then
            local success_box = ConfirmBox:new{
                title = "Cập nhật thành công! 🎉",
                text = string.format(
                    "Đã nâng cấp Truyện Việt lên phiên bản %s!\n\nBạn có muốn khởi động lại KOReader ngay bây giờ để áp dụng phiên bản mới không?",
                    latest_version
                ),
                ok_text = "Khởi động lại ngay",
                ok_callback = function()
                    self:restartKOReader()
                end,
                cancel_text = "Để sau",
                cancel_callback = function()
                    if on_finish then on_finish() end
                end,
            }
            UIManager:show(success_box)
        else
            local err_box = ConfirmBox:new{
                title = "Cập nhật thất bại",
                text = "Quá trình cập nhật gặp lỗi:\n" .. tostring(err),
                ok_text = "Đóng",
                ok_callback = function()
                    if on_finish then on_finish() end
                end,
            }
            UIManager:show(err_box)
        end
    end)
end

--- Kiểm tra cập nhật thủ công từ menu người dùng
function Updater:checkManually(on_return)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local ConfirmBox = require("ui/widget/confirmbox")
    local NetworkMgr = require("ui/network/networkmgr")
    local Trapper = require("ui/trapper")

    NetworkMgr:runWhenOnline(function()
        Trapper:wrap(function()
            local loading = InfoMessage:new{
                title = "Truyện Việt OTA",
                text = "Đang kiểm tra phiên bản mới từ máy chủ...",
                dismissable = false,
            }
            UIManager:show(loading)
            UIManager:forceRePaint()

            self:checkForUpdate(function(has_update, info, err)
                UIManager:close(loading)

                if err then
                    UIManager:show(ConfirmBox:new{
                        title = "Kiểm tra cập nhật",
                        text = "Không thể kiểm tra cập nhật:\n" .. tostring(err),
                        ok_text = "Đóng",
                        ok_callback = on_return,
                    })
                    return
                end

                if has_update and info then
                    self:showUpdateDialog(info, on_return)
                else
                    UIManager:show(ConfirmBox:new{
                        title = "Kiểm tra cập nhật",
                        text = "Bạn đang sử dụng phiên bản mới nhất (" .. Version .. ")",
                        ok_text = "Đóng",
                        ok_callback = on_return,
                    })
                end
            end)
        end)
    end)
end

--- Lập lịch kiểm tra cập nhật tự động chạy ngầm khi khởi động
function Updater:scheduleBackgroundCheck()
    if not Storage:isAutoUpdateCheckEnabled() then
        Debug.write("[OTA] Auto-check is disabled in settings.")
        return
    end

    local last_check = Storage:getLastUpdateCheckTime()
    local freq = Storage:getUpdateCheckFrequency()
    local now = os.time()

    if (now - last_check) < freq then
        Debug.write(string.format("[OTA] Skipped check: %d seconds since last check (freq: %d)", (now - last_check), freq))
        return
    end

    local UIManager = require("ui/uimanager")
    local NetworkMgr = require("ui/network/networkmgr")

    -- Chờ 8 giây sau khi khởi động để hệ thống ổn định
    UIManager:scheduleIn(8, function()
        if not NetworkMgr:isOnline() then
            Debug.write("[OTA] Background check postponed: device is offline.")
            return
        end

        Debug.write("[OTA] Starting background update check...")
        self:checkForUpdate(function(has_update, info, err)
            Storage:setLastUpdateCheckTime(os.time())
            if has_update and info then
                local ignored = Storage:getIgnoredUpdateVersion()
                if ignored and ignored == info.latest_version then
                    Debug.write("[OTA] Ignored update version: " .. tostring(ignored))
                    return
                end

                Debug.write("[OTA] New version found in background: " .. tostring(info.latest_version))
                UIManager:nextTick(function()
                    self:showUpdateDialog(info)
                end)
            end
        end)
    end)
end

return Updater
