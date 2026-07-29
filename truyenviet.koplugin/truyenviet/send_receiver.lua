local Http = require("truyenviet/http_client")
local Storage = require("truyenviet/storage")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local ffiutil = require("ffi/util")

local SendReceiver = {
    base_url = "https://send.nghiendoc.com",
    active_key = nil,
    is_polling = false,
    active_dialog = nil,
}

function SendReceiver:generateKey()
    local url = self.base_url .. "/generate"
    local res, err = Http:get(url, {
        ["User-Agent"] = "Mozilla/5.0 (Kobo Touch)"
    })
    if not res then return nil, err or "Không kết nối được server" end

    local json = require("json")
    local ok, data = pcall(json.decode, res)
    if ok and data and data.key then
        self.active_key = data.key
        return data.key
    end
    return nil, "Không giải mã được mã từ server"
end

function SendReceiver:checkStatus(key)
    key = key or self.active_key
    if not key then return nil, "Thiếu mã key" end

    local url = self.base_url .. "/status/" .. key
    local res, err = Http:get(url, {
        ["User-Agent"] = "Mozilla/5.0 (Kobo Touch)"
    })
    if not res then return nil, err end

    local json = require("json")
    local ok, data = pcall(json.decode, res)
    if ok and data then
        return data
    end
    return nil, "Dữ liệu trả về không hợp lệ"
end

function SendReceiver:downloadFile(filename, key, on_complete)
    key = key or self.active_key
    if not key or not filename then
        if on_complete then on_complete(false, "Thiếu thông tin tệp") end
        return
    end

    local file_url = self.base_url .. "/" .. ffiutil.urlEncode(filename) .. "?key=" .. key
    local dest_dir = Storage:getRootDir()
    local dest_path = ffiutil.joinPath(dest_dir, filename)

    UIManager:nextTick(function()
        local body, err = Http:get(file_url, {
            ["User-Agent"] = "Mozilla/5.0 (Kobo Touch)"
        })
        if not body or #body < 10 then
            if on_complete then on_complete(false, err or "Không thể tải tệp") end
            return
        end

        local f, open_err = io.open(dest_path, "wb")
        if not f then
            if on_complete then on_complete(false, open_err or "Không tạo được tệp trên đĩa") end
            return
        end
        f:write(body)
        f:close()

        if on_complete then on_complete(true, dest_path) end
    end)
end

function SendReceiver:showReceiveDialog(on_close)
    local key, err = self:generateKey()
    if not key then
        UIManager:show(InfoMessage:new{
            title = "Send to E-Reader",
            text = "Không thể tạo mã nhận truyện:\n" .. tostring(err)
        })
        return
    end

    self.is_polling = true

    local function startPollingLoop(current_key)
        if not self.is_polling or self.active_key ~= current_key then return end

        UIManager:scheduleIn(3, function()
            if not self.is_polling or self.active_key ~= current_key then return end

            local data, status_err = self:checkStatus(current_key)
            if data and data.file and data.file.name then
                self.is_polling = false
                if self.active_dialog then
                    UIManager:close(self.active_dialog)
                    self.active_dialog = nil
                end

                local filename = data.file.name
                UIManager:show(ConfirmBox:new{
                    title = "Nhận tệp thành công",
                    text = "🎉 Đã phát hiện tệp mới từ PC/Điện thoại:\n[" .. filename .. "]\n\nĐang tiến hành tải về máy đọc sách...",
                    ok_text = "📥 Tải Ngay",
                    cancel_text = "Bỏ qua",
                    ok_callback = function()
                        self:downloadFile(filename, current_key, function(success, result)
                            if success then
                                UIManager:show(ConfirmBox:new{
                                    title = "Tải tệp thành công",
                                    text = "✅ Đã lưu tệp vào máy đọc sách:\n" .. tostring(result) .. "\n\nBạn có muốn mở đọc tệp này ngay không?",
                                    ok_text = "📖 Mở Đọc Ngay",
                                    cancel_text = "Đóng",
                                    ok_callback = function()
                                        local ReaderUI = require("apps/reader/readerui")
                                        if ReaderUI then
                                            ReaderUI:showReader(result)
                                        end
                                    end,
                                    cancel_callback = function()
                                        if on_close then on_close() end
                                    end
                                })
                            else
                                UIManager:show(InfoMessage:new{
                                    title = "Lỗi tải tệp",
                                    text = "Không thể tải tệp về: " .. tostring(result)
                                })
                            end
                        end)
                    end,
                    cancel_callback = function()
                        if on_close then on_close() end
                    end
                })
            else
                -- Tiếp tục lắng nghe mỗi 3 giây để giữ mã key tồn tại liên tục trên server
                startPollingLoop(current_key)
            end
        end)
    end

    local dialog_text = table.concat({
        "📲 NHẬN TRUYỆN TỪ THIẾT BỊ KHÁC",
        "Trang web: https://send.nghiendoc.com",
        "---------------------------------------",
        "🔑 MÃ XÁC NHẬN CỦA BẠN (Đang giữ kết nối):",
        "       👉 [  " .. key .. "  ] 👈",
        "---------------------------------------",
        "Hướng dẫn gửi truyện từ Điện thoại / Máy tính:",
        "1. Mở trình duyệt web: send.nghiendoc.com",
        "2. Nhập mã key 4 ký tự: " .. key,
        "3. Chọn tệp truyện (EPUB, MOBI, PDF, TXT) và bấm 'Tải lên và Gửi'.",
        "",
        "🔄 Đang tự động lắng nghe & giữ mã kết nối...",
    }, "\n")

    self.active_dialog = ConfirmBox:new{
        title = "Send to E-Reader (send.nghiendoc.com)",
        text = dialog_text,
        ok_text = "🔄 Tạo Mã Mới",
        cancel_text = "❌ Đóng",
        ok_callback = function()
            self.is_polling = false
            self:showReceiveDialog(on_close)
        end,
        cancel_callback = function()
            self.is_polling = false
            if on_close then on_close() end
        end,
    }

    UIManager:show(self.active_dialog)
    startPollingLoop(key)
end

return SendReceiver
