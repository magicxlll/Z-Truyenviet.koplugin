local Http = require("truyenviet/http_client")
local Storage = require("truyenviet/storage")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local ffiutil = require("ffi/util")

local SendReceiver = {
    base_url = "https://send.nghiendoc.com",
    active_key = nil,
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

    local function showStatusBox(current_key)
        local key_text = current_key or "----"
        local dialog_text = table.concat({
            "📲 NHẬN TRUYỆN TỪ THIẾT BỊ KHÁC",
            "Trang web: send.nghiendoc.com",
            "---------------------------------------",
            "🔑 MÃ XÁC NHẬN CỦA BẠN:",
            "       👉 [  " .. key_text .. "  ] 👈",
            "---------------------------------------",
            "Hướng dẫn gửi truyện từ Điện thoại / Máy tính:",
            "1. Mở trang: https://send.nghiendoc.com",
            "2. Nhập mã key 4 ký tự: " .. key_text,
            "3. Chọn tệp truyện (EPUB, MOBI, PDF, TXT) hoặc dán URL và bấm Gửi.",
            "",
            "Bấm 'Kiểm tra tệp' bên dưới để nhận ngay!",
        }, "\n")

        UIManager:show(ConfirmBox:new{
            title = "Send to E-Reader (send.nghiendoc.com)",
            text = dialog_text,
            ok_text = "📥 Kiểm tra tệp",
            cancel_text = "❌ Đóng",
            ok_callback = function()
                local data, status_err = SendReceiver:checkStatus(current_key)
                if data and data.file and data.file.name then
                    local filename = data.file.name
                    UIManager:show(ConfirmBox:new{
                        title = "Nhận tệp thành công",
                        text = "🎉 Đã phát hiện tệp: " .. filename .. "\n\nBạn có muốn tải về máy đọc sách ngay bây giờ không?",
                        ok_text = "📥 Tải Về Ngay",
                        cancel_text = "Hủy",
                        ok_callback = function()
                            SendReceiver:downloadFile(filename, current_key, function(success, result)
                                if success then
                                    UIManager:show(ConfirmBox:new{
                                        title = "Tải tệp thành công",
                                        text = "✅ Đã lưu tệp vào máy đọc sách:\n" .. tostring(result) .. "\n\nBạn có muốn mở đọc tệp này ngay không?",
                                        ok_text = "📖 Mở Đọc",
                                        cancel_text = "Đóng",
                                        ok_callback = function()
                                            local ReaderUI = require("apps/reader/readerui")
                                            if ReaderUI then
                                                ReaderUI:showReader(result)
                                            end
                                        end,
                                    })
                                else
                                    UIManager:show(InfoMessage:new{
                                        title = "Lỗi tải tệp",
                                        text = "Không thể tải tệp về: " .. tostring(result)
                                    })
                                end
                            end)
                        end,
                    })
                elseif data and data.urls and #data.urls > 0 then
                    local received_url = data.urls[1]
                    UIManager:show(InfoMessage:new{
                        title = "Nhận Liên Kết",
                        text = "🔗 Đã nhận đường dẫn:\n" .. received_url
                    })
                else
                    UIManager:show(InfoMessage:new{
                        title = "Đang chờ tệp",
                        text = "Chưa phát hiện tệp nào được gửi cho mã [" .. current_key .. "].\n\nVui lòng đảm bảo đã bấm 'Tải lên và Gửi' trên trang send.nghiendoc.com!"
                    })
                end
            end,
            cancel_callback = function()
                if on_close then on_close() end
            end,
        })
    end

    showStatusBox(key)
end

return SendReceiver
