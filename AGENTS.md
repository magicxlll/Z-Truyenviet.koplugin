# Project Rules for Z-Truyenviet.koplugin

## 🚨 MANDATORY WORKFLOW AFTER EVERY DEBUG SESSION

Mỗi khi agent hoàn thành việc **sửa lỗi (debug), tối ưu hóa hoặc cập nhật mã nguồn** của ứng dụng/plugin này, agent **BẮT BUỘC** phải tự động thực hiện tuần tự các bước sau mà không cần chờ người dùng nhắc nhở:

### 1. Kiểm tra Cú pháp & Compile (Validation)
Kiểm tra tính toàn vẹn cú pháp của toàn bộ mã nguồn Lua bằng runtime LuaJIT:
```sh
find truyenviet.koplugin -name "*.lua" -exec luajit -b {} /dev/null \;
```

### 2. Build Ứng dụng (Build App)
Chạy script đóng gói bản phát hành để tạo file zip mới nhất trong thư mục `dist/`:
```sh
./scripts/build.sh
```
*Lưu ý: Đảm bảo file `dist/truyenviet.koplugin.zip` được tạo mới thành công.*

### 3. Cập nhật Bộ nhớ & Tài liệu Dự án
- Cập nhật các bài học kinh nghiệm, nguyên nhân lỗi và giải pháp vào file [Project_memory.md](file:///Volumes/ZMac1TB/Workspace/StudioProjects/Z-Truyenviet.koplugin/Project_memory.md).
- Nếu có cập nhật phiên bản hoặc số build, đồng bộ hóa tại:
  - [truyenviet/version.lua](file:///Volumes/ZMac1TB/Workspace/StudioProjects/Z-Truyenviet.koplugin/truyenviet.koplugin/truyenviet/version.lua)
  - [CHANGELOG.md](file:///Volumes/ZMac1TB/Workspace/StudioProjects/Z-Truyenviet.koplugin/CHANGELOG.md)

### 4. Đẩy mã nguồn lên Git (Push App to Git)
Tạo commit tóm tắt rõ ràng về lỗi vừa sửa và phiên bản, sau đó đẩy lên remote repository:
```sh
git add -A
git commit -m "<loại: feat/fix/chore>: <Tóm tắt thay đổi và phiên bản/BUILD>"
git push origin main
```

---

## ⚠️ Coding Guidelines & Constraints
- **Môi trường:** Tuân thủ chuẩn Lua 5.1/LuaJIT của KOReader. Không dùng tính năng của Lua 5.4+ (ví dụ gán lại biến lặp trong vòng lặp generic `for`).
- **An toàn Coroutine:** Tuyệt đối không gọi `coroutine.yield()` trực tiếp mà không kiểm tra `if coroutine.running() then coroutine.yield(...) end`.
- **An toàn Sắp xếp Chương:** Khi sắp xếp mục lục, ưu tiên so sánh số chương dạng số (`a.number < b.number`) trước khi fallback sang `Util.naturalCompare`.
- **E-ink RAM Constraints:** Không bao giờ log chuỗi nhị phân lớn vào file debug text; giới hạn prefetch ảnh bìa tối đa 10 ảnh.
