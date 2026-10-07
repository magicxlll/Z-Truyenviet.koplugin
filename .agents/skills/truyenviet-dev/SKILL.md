---
name: truyenviet-dev
description: >-
  Hướng dẫn phát triển, cào nguồn mới, debug và vận hành cho plugin Truyện Việt (KOReader).
  Bao gồm quy trình kiểm thử, đóng gói build và đẩy commit lên Git sau mỗi lần debug.
---

# Kỹ năng Phát triển Plugin Truyện Việt (KOReader)

Bộ kỹ năng này hướng dẫn quy trình phát triển, sửa lỗi (debug), kiểm thử và phát hành cho plugin **Truyện Việt (Z-Truyenviet.koplugin)** trên hệ thống **KOReader**.

---

## 1. Nguyên tắc Cốt lõi của Môi trường KOReader

1. **Runtime:** LuaJIT trong KOReader tương thích chuẩn Lua 5.1, hỗ trợ FFI. Không sử dụng các cú pháp chỉ có từ Lua 5.4+ (ví dụ gán lại biến lặp trong vòng lặp generic `for`).
2. **Tài nguyên E-ink:** Thiết bị máy đọc sách có RAM hạn chế (512MB - 1GB) và CPU xung nhịp thấp.
   - Tuyệt đối không log chuỗi nhị phân (ảnh, file nén).
   - Giới hạn prefetch ảnh bìa tối đa 10 ảnh.
   - Giải phóng bộ nhớ chuỗi HTML lớn sau khi bóc tách xong.
3. **Mạng & HTTPS:** Sử dụng `truyenviet/http_client.lua` để tận dụng cơ chế fallback tự động sang `curl -skSL` khi gặp lỗi SSL handshake hoặc chứng chỉ quá hạn trên thiết bị cũ.

---

## 2. Quy trình Thêm hoặc Sửa một Nguồn Truyện (`sources/*.lua`)

### Bước 1: Khảo sát Website (Ưu tiên API)
- Mở DevTools (F12) trên trình duyệt máy tính -> Tab **Network** -> Filter **Fetch/XHR**.
- **Nếu web có REST API JSON:** Lập tức sử dụng phương pháp cào JSON (`json.decode`). Đây là cách ổn định và nhanh nhất (xem ví dụ `blhvip.lua`).
- **Nếu web render HTML tĩnh:** Dùng Regex Lua (`string.match`, `string.gmatch`). Bóc tách theo selector đặc trưng và dùng `Util.stripTags`, `Util.decodeHtml`.

### Bước 2: Chuẩn hóa Interface của Module Nguồn
Mỗi file trong `truyenviet/sources/<ten_nguon>.lua` phải cung cấp đủ các phương thức:
- `search(query, page)`: Tìm kiếm truyện.
- `getGenres()` / `getCompleted(page)`: Danh mục duyệt truyện.
- `getStoryDetails(story)` hoặc `parseStory(html, story)`: Lấy thông tin bìa, tác giả, mô tả.
- `getChapters(story)` / `getAllChapters(story)`: Lấy danh sách chương. **Lưu ý:** Nếu có số chương, luôn sắp xếp theo số học trước, không sắp xếp thuần túy bằng `naturalCompare` chuỗi.
- `getChapter(chapter)`: Lấy nội dung chữ hoặc danh sách ảnh (nếu là truyện tranh).

### Bước 3: Đăng ký Nguồn
- Mở `truyenviet/source_registry.lua`.
- Thêm module vào mảng `BUILTIN_SOURCES`.

---

## 3. Quy trình Kiểm thử (Testing & Verification)

### Kiểm tra cú pháp (Syntax Validation):
```sh
find truyenviet.koplugin -name "*.lua" -exec luajit -b {} /dev/null \;
```

### Chạy Unit Test an toàn:
Khi viết test trong `spec/`:
- Luôn mock các module hệ thống của KOReader: `logger`, `datastorage`, `device`, `util`.
- Khi gọi `ChapterDownloader:download`, luôn kiểm tra coroutine hoặc bọc trong `coroutine.create`.

---

## 4. QUY TẮC BẮT BUỘC SAU MỖI LẦN DEBUG APP

Sau khi hoàn thành bất kỳ phiên debug hoặc sửa lỗi nào trên plugin:

1. **Kiểm tra cú pháp toàn bộ file Lua:**
   ```sh
   find truyenviet.koplugin -name "*.lua" -exec luajit -b {} /dev/null \;
   ```
2. **Build đóng gói ứng dụng:**
   ```sh
   ./scripts/build.sh
   ```
   Lệnh này sẽ cập nhật gói phát hành `dist/truyenviet.koplugin.zip`.

3. **Cập nhật Bộ nhớ Dự án:**
   - Mở `Project_memory.md`.
   - Cập nhật bài học kinh nghiệm, nguyên nhân lỗi và cách giải quyết vào mục tương ứng.
   - Nếu có tăng build/version, cập nhật đồng bộ tại `truyenviet/version.lua` và `CHANGELOG.md`.

4. **Commit và Push lên Git với tóm tắt phiên bản:**
   ```sh
   git add -A
   git commit -m "fix/feat: <Tóm tắt ngắn gọn lỗi đã fix hoặc tính năng mới> (<Phiên bản/BUILD>)"
   git push origin main
   ```
