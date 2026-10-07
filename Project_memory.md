# Project Memory: Z-Truyenviet.koplugin

Tài liệu lưu trữ bộ nhớ dự án, tổng hợp kiến trúc, tình trạng kỹ thuật hiện tại, danh mục nguồn truyện, các bài học kinh nghiệm qua các phiên bản và quy trình vận hành/phát triển cho plugin **Truyện Việt** trên hệ điều hành **KOReader**.

---

## 1. Thông tin chung & Tình trạng phiên bản

| Thuộc tính | Chi tiết |
| :--- | :--- |
| **Tên Plugin** | `truyenviet` (Hiển thị: *Truyện Việt*) |
| **Mục tiêu** | Tìm kiếm, duyệt danh mục, tải về và đọc truyện chữ / truyện tranh trực tiếp từ các website truyện Việt Nam trên máy đọc sách chạy KOReader (Kindle, Kobo, Android, v.v.). |
| **Phiên bản hiện tại** | Codebase: `v3.8.0` / `3.9.4` (`BUILD-1368`) |
| **Ngôn ngữ & Runtime** | LuaJIT (tương thích môi trường Lua 5.1/LuaJIT của KOReader) |
| **Async Engine** | Copas 4.x + LuaSocket + Timerwheel + Binaryheap |
| **Kho lưu trữ Git** | `https://github.com/magicxlll/Z-Truyenviet.koplugin.git` (nhánh `main`) |
| **Build Artifact** | `dist/truyenviet.koplugin.zip` |

---

## 2. Kiến trúc Hệ thống (System Architecture)

```mermaid
flowchart TD
    subgraph KOReader_Core["KOReader Host Environment"]
        Dispatcher["Dispatcher (ZenUI / Hotkeys)"]
        MainMenu["MainMenu / TitleBar"]
        ReaderUI["ReaderUI (EPUB/HTML Document Reader)"]
        KO_LFS["KOReader LFS / NetworkMgr"]
    end

    subgraph Truyenviet_UI["Phân hệ Giao diện (truyenviet/ui & widgets)"]
        MainPlugin["main.lua (Plugin Entrypoint)"]
        BrowserUI["browser.lua (Monolith UI Controller - 4.2k lines)"]
        StoryResultsWidget["widgets/story_results.lua"]
        FontHelper["font_helper.lua"]
    end

    subgraph Truyenviet_Core["Phân hệ Xử lý Lõi (Core Services)"]
        SearchService["search_service.lua"]
        ChapterDownloader["chapter_downloader.lua"]
        DocBuilder["document_builder.lua (HTML/EPUB Gen)"]
        ChapterOrder["chapter_order.lua"]
        CoverCache["cover_cache.lua (MD5/SHA Hash, Max 10 Prefetch)"]
        Storage["storage.lua (DataStorage wrapper)"]
        CredMgr["credential_manager.lua (Tài khoản VIP)"]
        ErrRep["error_reporter.lua (GitHub Issue Bot)"]
        Debugger["debugger.lua (truyenviet-debug.txt)"]
    end

    subgraph Network_Layer["Phân hệ Mạng & Async"]
        HttpClient["http_client.lua (LuaSocket + curl Fallback + CF Detect)"]
        CopasAsync["copas.lua & copas/ (Non-blocking I/O)"]
    end

    subgraph Sources_Layer["Phân hệ Nguồn Truyện (21+ sources)"]
        Registry["source_registry.lua"]
        BuiltinSources["sources/*.lua (truyenfull, akaytruyen, docln, v.v.)"]
        GenericSource["generic_source.lua (Engine cào từ JSON schema)"]
        CustomJson["custom_sources/*.json"]
    end

    Dispatcher --> MainPlugin
    MainMenu --> MainPlugin
    MainPlugin --> BrowserUI
    BrowserUI --> SearchService
    BrowserUI --> ChapterDownloader
    BrowserUI --> CoverCache
    BrowserUI --> ReaderUI
    SearchService --> Registry
    ChapterDownloader --> DocBuilder
    DocBuilder --> Storage
    Registry --> BuiltinSources
    Registry --> GenericSource
    GenericSource --> CustomJson
    BuiltinSources --> HttpClient
    HttpClient --> CopasAsync
```

### Bản đồ Module và Trách nhiệm:

1. **`main.lua`**: Điểm vào của plugin, đăng ký menu KOReader, nút topbar, và các hành động Dispatcher (`start_truyenviet`, `truyenviet_continue`, `truyenviet_history`, `truyenviet_downloaded`, v.v.). Tương thích ZenUI thông qua gán `plugin = true`.
2. **`truyenviet/browser.lua`**: Controller giao diện trung tâm điều hướng tất cả menu (duyệt nguồn, tìm kiếm, xem chi tiết truyện, chọn chương, tải chương, lịch sử, cài đặt). Hiện tại là module nguyên khối lớn (>4,200 dòng).
3. **`truyenviet/http_client.lua`**: Quản lý request HTTP/HTTPS với cơ chế fallback kép:
   - Thử `socket.http` nội tại.
   - Nếu gặp SSL khắt khe hoặc handshake lỗi, tự động chuyển sang gọi lệnh CLI `curl -skSL` ở tầng OS.
   - Nhận diện màn hình xác thực Cloudflare Challenge.
4. **`truyenviet/source_registry.lua`**: Đăng ký và nạp các nguồn truyện tích hợp sẵn và tải động các nguồn từ thư mục `custom_sources/*.json`.
5. **`truyenviet/chapter_downloader.lua`**: Quản lý tiến trình tải chương đồng bộ hoặc bất đồng bộ qua Copas, tránh nghẽn UI của máy đọc sách.
6. **`truyenviet/document_builder.lua`**: Dựng file đọc dạng HTML/EPUB lưu trữ cục bộ cho KOReader mở, tích hợp làm sạch CSS và lọc quảng cáo.
7. **`truyenviet/credential_manager.lua`**: Quản lý tài khoản đăng nhập (VIP) của các nguồn yêu cầu xác thực (AkayTruyen, TVE-4U).
8. **`truyenviet/storage.lua`**: Đọc/ghi cấu hình và trạng thái qua `datastorage` của KOReader.

---

## 3. Danh mục 21+ Nguồn truyện (Source Catalog)

| ID | Tên Nguồn | Tên miền mặc định | Loại | Kỹ thuật cào | Ghi chú đặc biệt |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `truyenfull` | Truyện Full | `https://truyenfull.io` | Text | HTML Regex | Nguồn phổ biến, hỗ trợ pagination regex |
| `truyenqq` | Truyện QQ | `https://truyenqqto.com` | Comic | HTML Regex | Truyện tranh, cào danh sách ảnh chương |
| `dualeo` | Dưa Leo Truyện | `https://dualeotruyen5.com` | Comic | HTML Regex | Truyện tranh |
| `truyendich` | Truyện Dịch | `https://truyendich.com` | Text | HTML Regex | Danh mục phong phú |
| `cbunu` | Cbunu | `https://cbunu.com` | Text | HTML + Session | Cần quản lý Set-Cookie trang chủ |
| `haccbl` | Hắc Cbl | `https://haccbl.top` | Text | HTML + AES/PBKDF2 | Giải mã nội dung chương mã hóa JS |
| `giatocvuongtai` | Gia Tộc Vương Tài | `https://giatocvuongtai.com` | Text | JSON/HTML | Parse JSON metadata |
| `docln` | Cổng Light Novel | `https://docln.net` | Text | HTML Regex + RateLimit | Giới hạn 1.2s/request chống chặn IP |
| `tve4u` | TVE-4U | `https://tve-4u.org` | Forum | XenForo API/HTML | Diễn đàn ebook, yêu cầu đăng nhập |
| `dilib` | DiLib | `https://dilib.vn` | Text | REST/HTML | Hỗ trợ phân trang và tìm kiếm |
| `mizzya` | Mizzya | `https://mizzya.com` | Text | HTML Regex | Nguồn truyện nhẹ |
| `metruyenvn` | Mê Truyện VN | `https://metruyen.net.vn` | Text | HTML Regex | Phân trang và tìm kiếm theo danh mục |
| `aztruyen` | AZ Truyện | `https://aztruyen.com` | Text | HTML Regex | Nhiều danh mục hot/hoàn thành |
| `dualeotruyenfull`| Dưa Leo Full | `https://dualeotruyenfull.com` | Text | HTML Regex | Phiên bản chữ |
| `truyenc` | Truyện C | `https://truyenc.com` | Text | HTML Regex | Cover URL thường chứa khoảng trắng thô |
| `akaytruyen` | Akay Truyện | `https://akaytruyen.com` | Text | AJAX/HTML + VIP Auth | Cache DOM section, endpoint `/search-chapters` |
| `storyaclick` | Story A Click | `https://storyaclick.com` | Text | HTML Regex | Nguồn mới |
| `blhvip` | BLH VIP | `https://api.blhvip.vn` | Text | **REST API (JSON)** | Cào qua REST API backend, nhanh & ổn định |
| `metruyenchuvn` | Mê Truyện Chữ VN | `https://metruyenchuvn.com` | Text | HTML Regex | Parsing DOM chuẩn |
| `conduongbachu` | Con Đường Bá Chủ | `https://conduongbachu.com` | Text | **WordPress REST API** | `/wp-json/wp/v2/posts`, kiểm tra `X-WP-Total` |
| `xtruyen` | X-Truyện | `https://xtruyen.vn` | Text | **Zlib + Base64 decode** | Giải mã chuỗi mã hóa `data_x` qua `ffi/zlib` |

---

## 4. Các bài học kinh nghiệm xương máu (Lessons Learned)

### 4.1. Ưu tiên REST API ngầm thay vì Regex HTML
- **Bài học:** Cào HTML truyền thống (`string.match`) dễ vỡ khi web đổi layout. Điển hình: `blhvip` dùng REST API (`api.blhvip.vn/v1/...`) và `conduongbachu` dùng WordPress REST API (`wp-json/wp/v2/posts`) giúp code gọn hơn 70%, tốc độ phản hồi nhanh hơn gấp nhiều lần và không bị ảnh hưởng bởi cập nhật CSS.
- **Quy tắc:** Luôn dùng F12 DevTools (Tab Network -> Filter `Fetch/XHR`) trước khi viết regex HTML.

### 4.2. Xử lý phân trang WordPress REST (`X-WP-Total`)
- **Sự cố BUILD-1324:** Khi cào nguồn `conduongbachu`, nếu một trang request giữa chừng bị timeout, plugin lưu bộ đệm mục lục bị cụt khiến người đọc bị mất chương.
- **Giải pháp:** Chỉ công nhận danh mục hoàn thành khi số lượng bài cào được khớp chính xác với header `X-WP-Total` do server trả về.

### 4.3. Cạm bẫy sắp xếp chương: `Natural Compare` vs Số chương thực tế
- **Sự cố:** `helpers.naturalCompare` quy định kiểu `number` đứng trước `string`. Tiêu đề bắt đầu bằng số như `"201: VÔ ĐỀ."` bị đẩy lên đứng trước `"Chương 1: Khởi đầu"`.
- **Bài học:** Khi sắp xếp danh sách chương, nếu cả hai chương đều bóc tách được số hiệu chương (`a.number` và `b.number`), luôn so sánh số học `a.number < b.number` trước; chỉ fallback sang `naturalCompare` trên chuỗi tiêu đề khi không có số chương.

### 4.4. An toàn Coroutine trong LuaJIT
- **Sự cố:** `ChapterDownloader:download` gọi thẳng `coroutine.yield()` để cập nhật thanh tiến trình. Khi chạy trong luồng chính (main thread) hoặc môi trường test đơn vị mà không được bọc bởi coroutine, LuaJIT sẽ văng lỗi nghiêm trọng: `attempt to yield across C-call boundary`.
- **Giải pháp:** Luôn kiểm tra `if coroutine.running() then coroutine.yield(...) end`.

### 4.5. Tác dụng phụ của Monkey-Patching (`helpers.lua`)
- **Sự cố:** `truyenviet/helpers.lua` ghi đè trực tiếp hàm toàn cục `ko_util.urlEncode = Util.urlEncode`. `Util.urlEncode` mã hóa ký tự `@` thành `%40`, làm sai lệch các đoạn mã kiểm thử hoặc module khác kỳ vọng `@` được giữ nguyên.
- **Bài học:** Hạn chế tối đa việc ghi đè module chia sẻ (`ko_util`). Nên gọi trực tiếp `Util.urlEncode` trong các module thuộc phạm vi plugin.

### 4.6. Vấn đề bộ nhớ (RAM) trên máy đọc sách E-ink
- Thiết bị E-ink thường chỉ có 512MB - 1GB RAM, CPU đơn nhân hoặc tiết kiệm điện.
- Việc log chuỗi nhị phân (ảnh bìa raw) vào file text log từng gây lỗi `400 Problems parsing JSON` khi gửi báo lỗi GitHub và tràn RAM.
- Giới hạn ảnh prefetch cover tối đa 10 ảnh (`max_prefetch = 10`), không bao giờ nạp toàn bộ danh mục ảnh cùng lúc.

### 4.7. Cloudflare Challenge & Bảo mật HTTPS
- Môi trường KOReader chạy curl nhúng với cờ `-skSL` để bỏ qua lỗi chứng chỉ SSL cũ trên máy đọc sách cũ.
- Khi gặp Cloudflare JS challenge, bắt buộc nhận diện chuỗi `window._cf_chl_opt` hoặc `id="challenge-error-text"` để báo lỗi rõ ràng cho người dùng thay vì treo vòng lặp vô tận.

---

## 5. Nợ Kỹ thuật & Tồn đọng (Technical Debt)

1. **Bộ Test Suite bị lỗi (Cần sửa gấp):**
   - `spec/akaytruyen_test.lua`: Lỗi kỳ vọng `@` thay vì `%40` sau URL encoding.
   - `spec/chapter_downloader_test.lua`: Lỗi `coroutine.yield` trên main thread.
   - `spec/conduongbachu_test.lua`: Lỗi thứ tự sắp xếp chương 201 và chương 1.
   - `spec/document_builder_test.lua`: Thiếu mock `cleanChapterHtml` trong mock `helpers`.
   - `spec/parser_test.lua`: Thiếu mock `socket` do `docln.lua` require ở cấp module.
   - `spec/reader_test.lua`: Thiếu mock `logger`.
   - `spec/parser_spec.lua`: Thiếu mock `datastorage`.
2. **File rác trong Bundle Release:**
   - File `truyenviet.koplugin/truyenviet/sources/test_aeslua.lua` chứa đường dẫn Windows tĩnh `d:\Project\truyenfull\...` chưa được xóa và đang bị đóng gói vào `truyenviet.koplugin.zip`.
3. **Module nguyên khối `browser.lua`:**
   - Hơn 4,200 dòng trong một file duy nhất. Cần tách thành các view riêng: `views/main_menu.lua`, `views/story_detail.lua`, `views/chapter_selector.lua`, `views/settings.lua`.
4. **Hardcoded GitHub Token trong `error_reporter.lua`:**
   - Chứa chuỗi token bị đảo ngược (`table.concat(_P):reverse()`) nhắm vào repository của bên thứ ba, tiềm ẩn nguy cơ lộ lọt và lạm dụng API.
5. **Thư viện AES bị thiếu trong `credential_manager.lua`:**
   - Code gọi `aeslua` nhưng thư viện này không tồn tại trong source, dẫn tới việc lưu mật khẩu người dùng luôn fallback về thuật toán che giấu XOR yếu (`obf:...`).
6. **Không tương thích hoàn toàn với Lua 5.4+:**
   - `generic_source.lua:502`: Gán lại biến lặp `line = Util.trim(line)` bị cấm trong Lua 5.4+ (const variable).

---

## 6. Quy trình Vận hành Chuẩn (Runbook & Workflow)

### Quy trình Bắt buộc sau mỗi lần Debug App:
```mermaid
flowchart LR
    A["1. Sửa lỗi & Verify"] --> B["2. Syntax & Unit Test"]
    B --> C["3. Build App\n(./scripts/build.sh)"]
    C --> D["4. Cập nhật\nProject_memory.md"]
    D --> E["5. Git Commit & Push\n(Tóm tắt version)"]
```

1. **Kiểm tra cú pháp & kiểm thử:**
   ```sh
   find truyenviet.koplugin -name "*.lua" -exec luajit -b {} /dev/null \;
   ```
2. **Đóng gói bản phát hành:**
   ```sh
   ./scripts/build.sh
   # Sinh ra: dist/truyenviet.koplugin.zip
   ```
3. **Commit & Push Git:**
   ```sh
   git add truyenviet.koplugin/ dist/truyenviet.koplugin.zip Project_memory.md CHANGELOG.md
   git commit -m "fix/feat: <mô tả ngắn gọn về sửa lỗi và phiên bản>"
   git push origin main
   ```
