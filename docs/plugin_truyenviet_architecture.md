# Tổng quan về Cơ chế hoạt động của Plugin TruyenViet (KOReader)

Plugin **TruyenViet** là một tiện ích mở rộng dành cho máy đọc sách chạy hệ điều hành KOReader, giúp người dùng có thể tìm kiếm, duyệt danh mục, tải và đọc truyện chữ/truyện tranh trực tiếp từ các trang web truyện Việt Nam mà không cần trình duyệt.

Dưới đây là tóm tắt về kiến trúc và cách thức cào dữ liệu của plugin này.

---

## 1. Kiến trúc tổng thể của Plugin

Plugin được chia thành các phân hệ rõ ràng để dễ bảo trì và mở rộng:

1. **Giao diện người dùng (UI - `browser.lua`, thư mục `ui/`):**
   - Tích hợp trực tiếp vào hệ thống menu của KOReader.
   - Hiển thị danh sách truyện, thông tin chi tiết (ảnh bìa, tóm tắt), mục lục chương và giao diện đọc.
   - Xử lý các tương tác của người dùng (chuyển trang, tìm kiếm, lưu truyện yêu thích).

2. **Hệ thống mạng (`http_client.lua`):**
   - Xử lý toàn bộ các yêu cầu HTTP/HTTPS (GET, POST).
   - Tích hợp cơ chế dự phòng (**Fallback Mechanism**): Nếu `socket.http` nội tại của LuaJIT gặp lỗi (do giao thức HTTPS khắt khe), nó sẽ tự động chuyển sang gọi lệnh `curl` ở tầng hệ điều hành.
   - Hỗ trợ vượt rào chống bot cơ bản (Cloudflare/Anti-Bot) bằng cách thay đổi User-Agent, Headers hoặc Ciphers.

3. **Trình quản lý nguồn truyện (`source_registry.lua`):**
   - Quản lý danh sách các nguồn truyện (Built-in và Custom JSON).
   - Cho phép người dùng bật/tắt hoặc thay đổi thứ tự ưu tiên của các nguồn truyện hiển thị trên giao diện.

4. **Các module nguồn truyện (`sources/*.lua`):**
   - Trái tim của quá trình cào dữ liệu (Scraping).
   - Mỗi file (VD: `truyenfull.lua`, `blhvip.lua`) chịu trách nhiệm giao tiếp với một trang web cụ thể.
   - Bắt buộc tuân thủ một Interface chung (cấu trúc `Source`) để UI có thể gọi mà không cần biết logic bên trong.

---

## 2. Tiêu chuẩn của một Module Nguồn Truyện (Source Interface)

Mỗi file nguồn (ví dụ: `blhvip.lua`) phải định nghĩa các hàm cơ bản sau:

- `getGenres()`: Trả về danh sách các thể loại/danh mục (VD: Truyện Hot, Mới cập nhật) kèm theo hàm lấy dữ liệu của danh mục đó.
- `search(keyword, page)`: Tìm kiếm truyện theo từ khóa.
- `getDetails(url)`: Phân tích trang chi tiết truyện để lấy tên truyện, tác giả, ảnh bìa, tóm tắt và trạng thái (Đang ra/Hoàn thành).
- `getChapters(url)`: Lấy toàn bộ danh sách chương (số thứ tự, tên chương, link chương). Hỗ trợ xử lý phân trang nếu danh sách chương quá dài.
- `getChapterContent(url)`: Cào nội dung văn bản (hoặc hình ảnh) của một chương cụ thể và loại bỏ các thẻ HTML rác.

---

## 3. Cách thức "Cào" (Scraping) dữ liệu hiện nay

Do môi trường KOReader (LuaJIT) không có các thư viện phân tích cây DOM mạnh mẽ như BeautifulSoup (Python) hay Cheerio (NodeJS), việc cào dữ liệu đòi hỏi sự khéo léo và tối ưu qua 2 phương pháp chính:

### Phương pháp 1: Khai thác API ngầm (REST/JSON)
Đây là cách **hiệu quả, nhanh và ít lỗi nhất** áp dụng cho các trang web hiện đại (SPA - Single Page Application như Next.js, Nuxt.js, React).
- **Ví dụ thực tế:** Nguồn `blhvip`.
- **Cách làm:** 
  1. Dùng công cụ Network (F12) trên trình duyệt để tìm các luồng gọi API (ví dụ: `api.blhvip.vn/v1/search?q=...` hoặc `api.blhvip.vn/v1/story/slug/chapter_list`).
  2. Dùng thư viện `json.decode` nội tại của KOReader để chuyển chuỗi JSON thành bảng Lua (Table).
  3. Ánh xạ dữ liệu JSON (name, slug, id) vào cấu trúc chuẩn của Plugin.
- **Ưu điểm:** Bỏ qua hoàn toàn bước phân tích HTML, không bị ảnh hưởng khi giao diện web thay đổi, hỗ trợ tìm kiếm không dấu rất tốt (do backend của web tự xử lý).

### Phương pháp 2: Phân tích HTML bằng Biểu thức chính quy (Regex)
Áp dụng cho các trang web truyền thống render trực tiếp HTML (Server-Side Rendering) hoặc khi không thể tìm thấy API mở.
- **Ví dụ thực tế:** Nguồn `truyenfull`, `metruyenchuvn`, và danh sách hiển thị tĩnh của `blhvip` (`/truyen-hot`).
- **Cách làm:**
  1. Sử dụng hàm `string.match` và `string.gmatch` của Lua để bóc tách thông tin.
  2. Xác định các Class/ID đặc trưng bao bọc nội dung.
     - *Tìm link truyện:* Cắt đoạn `<a[^>]+href="([^"]+)"[^>]*class="title"[^>]*>([^<]*)</a>`
     - *Lấy nội dung chương:* Bắt đầu từ `<div id="chapter-content">` cho đến thẻ đóng tương ứng.
  3. Dùng các hàm tiện ích (`Util.stripTags`, `Util.absoluteUrl`) để xóa bỏ thẻ `<script>`, `<iframe>`, `<style>` và nối các đường dẫn tương đối thành tuyệt đối.
- **Ưu điểm:** Áp dụng được cho 90% các trang web truyện chữ.
- **Nhược điểm:** Phải bảo trì thường xuyên mỗi khi chủ web đổi cấu trúc thẻ HTML.

### Cơ chế vượt rào và bảo mật (Anti-Scraping Bypass)
Nhiều trang web hiện tại có cơ chế chặn Bot (Cloudflare, CAPTCHA). Plugin Truyenviet xử lý bằng cách:
1. **Quản lý Session Cookie:** Một số nguồn (như `cbunu`) yêu cầu cookie phiên. Plugin sẽ mô phỏng truy cập vào trang chủ trước, lấy header `Set-Cookie` và gắn nó vào các lệnh gọi tiếp theo.
2. **Cập nhật Base URL Động:** Cho phép thay đổi tên miền trong cài đặt (từ `.com` sang `.vn` hoặc `.net`) khi trang web bị chặn mạng hoặc đổi tên miền.

---

## 4. Quy trình thêm một nguồn truyện mới nhanh chóng

1. **Phân tích mục tiêu (Browser F12):** Khảo sát xem web dùng API (JSON) hay trả thẳng HTML. Ưu tiên tìm API.
2. **Tạo file `sources/[ten_nguon].lua`:** Khai báo cấu trúc cơ bản `Source`.
3. **Cài đặt `search` và `getGenres`:** Viết regex/json parsing để lấy danh sách truyện dạng thẻ ngắn (tên, link, ảnh bìa).
4. **Cài đặt `getDetails`:** Vào URL của truyện, bóc lấy ảnh bìa HD và mô tả nội dung.
5. **Cài đặt `getChapters`:** Bóc tách lấy mảng tên chương và link. Lưu ý kỹ cơ chế phân trang (while loop).
6. **Cài đặt `getChapterContent`:** Cắt lấy chính xác đoạn nội dung chữ, lọc bỏ thẻ `<br>` dư thừa hoặc quảng cáo chèn ngang.
7. **Kích hoạt:** Đăng ký tên nguồn vào danh sách trong `source_registry.lua`.
