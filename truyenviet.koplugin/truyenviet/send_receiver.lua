local Http = require("truyenviet/http_client")
local Storage = require("truyenviet/storage")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ffiutil = require("ffi/util")
local util = require("util")

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
    if not key or key == "" then return nil, "Thiếu mã key" end

    local url = self.base_url .. "/status/" .. key
    local res, err = Http:get(url, {
        ["User-Agent"] = "Mozilla/5.0 (Kobo Touch)"
    })
    if not res then return nil, err or "Không tìm thấy tệp hoặc mã đã hết hạn" end

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
    util.makePath(dest_dir)
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

function SendReceiver:fetchAndDownloadByKey(input_key, on_finish)
    local clean_key = util.trim(input_key or ""):upper()
    if #clean_key < 4 then
        UIManager:show(InfoMessage:new{
            title = "Send to E-Reader",
            text = "Vui lòng nhập đúng mã Key 4 ký tự!"
        })
        return
    end

    local data, err = self:checkStatus(clean_key)
    if not data or err then
        UIManager:show(InfoMessage:new{
            title = "Send to E-Reader",
            text = "❌ Không tìm thấy tệp cho mã [" .. clean_key .. "].\n\nNguyên nhân có thể do:\n1. Mã Key chưa chính xác.\n2. Chưa tải tệp lên tại send.nghiendoc.com.\n3. Mã đã quá 30 giây hết hạn."
        })
        return
    end

    if data.file and data.file.name then
        local filename = data.file.name
        UIManager:show(ConfirmBox:new{
            title = "Phát Hiện Tệp Mới",
            text = "🎉 Đã tìm thấy tệp: " .. filename .. "\n\nBạn có muốn tải về máy đọc sách ngay không?",
            ok_text = "📥 Tải Ngay",
            cancel_text = "Hủy",
            ok_callback = function()
                self:downloadFile(filename, clean_key, function(success, result)
                    if success then
                        UIManager:show(ConfirmBox:new{
                            title = "Tải Thành Công",
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
                                if on_finish then on_finish() end
                            end
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            title = "Lỗi Tải Tệp",
                            text = "Không thể tải tệp về: " .. tostring(result)
                        })
                    end
                end)
            end,
            cancel_callback = function()
                if on_finish then on_finish() end
            end
        })
    elseif data.urls and #data.urls > 0 then
        UIManager:show(InfoMessage:new{
            title = "Nhận Liên Kết",
            text = "🔗 Đã nhận liên kết:\n" .. tostring(data.urls[1])
        })
    else
        UIManager:show(InfoMessage:new{
            title = "Chưa Có Tệp",
            text = "Mã [" .. clean_key .. "] hợp lệ nhưng chưa có tệp nào được tải lên trên send.nghiendoc.com!"
        })
    end
end

function SendReceiver:showReceiveDialog(on_close)
    local ButtonDialog = require("ui/widget/buttondialog")

    UIManager:show(ButtonDialog:new{
        title = "📲 Send to E-Reader (send.nghiendoc.com)",
        text = "Nhận truyện không dây từ Điện thoại / Máy tính vào KOReader",
        buttons = {
            {
                {
                    text = "📥 Nhập Mã Key 4 Ký Tự (Từ PC/Web)",
                    callback = function()
                        UIManager:close(self.active_dialog)
                        UIManager:show(InputDialog:new{
                            title = "Nhập Mã Key 4 Ký Tự",
                            description = "Nhập 4 ký tự hiển thị trên trang send.nghiendoc.com (ví dụ: A7B9):",
                            text = "",
                            input_type = "string",
                            buttons = {
                                {
                                    {
                                        text = "Tải Về Ngay",
                                        callback = function(input_text)
                                            self:fetchAndDownloadByKey(input_text, on_close)
                                        end,
                                    },
                                    {
                                        text = "Hủy",
                                        callback = function()
                                            if on_close then on_close() end
                                        end,
                                    },
                                }
                            }
                        })
                    end,
                },
            },
            {
                {
                    text = "⚡ Tạo Mã Key Mới & Lắng Nghe Tự Động",
                    callback = function()
                        UIManager:close(self.active_dialog)
                        local key, err = self:generateKey()
                        if not key then
                            UIManager:show(InfoMessage:new{
                                title = "Lỗi tạo mã",
                                text = "Không thể tạo mã tự động: " .. tostring(err)
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
                                        title = "Phát Hiện Tệp Mới",
                                        text = "🎉 Đã phát hiện tệp: " .. filename .. "\n\nBấm Tải Ngay để lưu vào máy đọc sách!",
                                        ok_text = "📥 Tải Ngay",
                                        cancel_text = "Bỏ qua",
                                        ok_callback = function()
                                            self:downloadFile(filename, current_key, function(success, result)
                                                if success then
                                                    UIManager:show(ConfirmBox:new{
                                                        title = "Tải Thành Công",
                                                        text = "✅ Đã lưu tệp vào máy đọc sách:\n" .. tostring(result) .. "\n\nMở đọc ngay?",
                                                        ok_text = "📖 Mở Đọc",
                                                        cancel_text = "Đóng",
                                                        ok_callback = function()
                                                            local ReaderUI = require("apps/reader/readerui")
                                                            if ReaderUI then ReaderUI:showReader(result) end
                                                        end,
                                                    })
                                                else
                                                    UIManager:show(InfoMessage:new{
                                                        title = "Lỗi Tải Tệp",
                                                        text = "Không thể tải tệp: " .. tostring(result)
                                                    })
                                                end
                                            end)
                                        end,
                                    })
                                else
                                    startPollingLoop(current_key)
                                end
                            end)
                        end

                        local info_text = table.concat({
                            "🔑 MÃ XÁC NHẬN TỰ ĐỘNG: [  " .. key .. "  ]",
                            "---------------------------------------",
                            "1. Mở trang: https://send.nghiendoc.com",
                            "2. Nhập mã key: " .. key,
                            "3. Bấm 'Tải lên và Gửi'.",
                            "",
                            "🔄 Plugin đang tự động duy trì kết nối mã này...",
                        }, "\n")

                        self.active_dialog = ConfirmBox:new{
                            title = "Mã Nhận Tự Động: " .. key,
                            text = info_text,
                            ok_text = "📥 Kiểm tra ngay",
                            cancel_text = "Đóng",
                            ok_callback = function()
                                self:fetchAndDownloadByKey(key, on_close)
                            end,
                            cancel_callback = function()
                                self.is_polling = false
                                if on_close then on_close() end
                            end,
                        }
                        UIManager:show(self.active_dialog)
                        startPollingLoop(key)
                    end,
                },
            },
            {
                {
                    text = "❌ Đóng",
                    callback = function()
                        self.is_polling = false
                        if on_close then on_close() end
                    end,
                },
            },
        }
    })
end

return SendReceiver
