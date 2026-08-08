## 3.8.0 (BUILD-1368) - 2026-08-09

### Feature & Fixes
- **Nguồn `xtruyen`**:
  - Tích hợp thành công module giải nén Zlib (`ffi/zlib`) và giải mã chuỗi Base64 tùy biến để xử lý nội dung mã hóa `data_x` của nguồn `xtruyen.vn` trực tiếp trên KOReader. Khắc phục triệt để lỗi "Không tìm thấy nội dung chương" khi đọc truyện.
  - Bổ sung cơ chế trích xuất tên chương thật từ nội dung tải về (do Cloudflare chặn API mục lục), hiển thị đúng tên trên thanh tiêu đề khi đọc truyện.
  - Tự động sinh danh sách mục lục (Chương 1, Chương 2,...) để vượt qua lớp bảo vệ JS Challenge của Cloudflare đối với các API AJAX ẩn.
- **Hệ thống (ZenUI)**:
  - Cập nhật cờ `plugin = true` cho toàn bộ các đường dẫn nhanh (Dispatcher actions) như "Tiếp tục đọc", "Lịch sử đọc", "Đã tải xuống", giúp tính năng nhận diện chính xác và hiển thị đầy đủ bên trong mục Plugin của giao diện.
# Changelog

## 3.7.0 (BUILD-1341) - 2026-07-29

### Codex

- Giữ nguyên phiên bản ổn định `3.7.0`, chỉ tăng internal build từ 1340 lên
  1341 để đối chiếu kiểm thử tối ưu riêng nguồn AkayTruyen.
- Parse trang chủ đúng ba DOM section một lần, cache dữ liệu đã bóc tách thay
  vì giữ HTML gần 900 KB. Gom anchor ảnh/title theo URL và tái dùng cover từ
  mục Hot cho Truyện đang ra; không phát sinh request ảnh/trang bổ sung.
- Chuyển mục lục sang endpoint chính thức
  `/search-chapters?search=&page=N` (khoảng 140 KB/page thay cho trang truyện
  gần 469 KB), vẫn fallback trang đầy đủ nếu endpoint lỗi. Siết parser theo
  `chapter-link-mobile` + prefix truyện để không nhận link hành động.
- Thêm `getChapterAsync` và giới hạn `max_concurrent = 1` để rolling prefetch
  không dùng request đồng bộ chặn UI. Parser chương cắt thẳng vùng
  `#chapter-content` trước `chapter-nav`, chỉ sanitize phần nội dung cần thiết.
- Regression Akay đạt 39 assertion, 35 file Lua compile. Live test đạt Hot
  36/36 cover, Đang ra 32/32, Hoàn thành 4/4, Chủ đề 18/18; tìm kiếm đúng,
  *Chung Cực Truyền Kỳ* đủ 324 chương/7 trang và chương mới có 25.425 ký tự.

## 3.4.3 (BUILD-1325) - 2026-07-29

### Codex

- Làm lại phân trang nguồn **Con Đường Bá Chủ** theo REST API WordPress tăng
  dần: mở một trang chỉ tải đúng một trang API, còn `Tải tất cả` chỉ lưu chỉ
  mục khi đã nhận đủ toàn bộ số bài mà `X-WP-Total` công bố. Request lỗi giữa
  chừng không còn bị cache thành danh sách chương cụt.
- Giữ từng bài WordPress theo URL, bao gồm hai bài cùng số **3059** và slug
  legacy `/3399-vo-de/`; kiểm tra không bỏ sót bài chính truyện và không tự
  sinh chương không tồn tại **3509**.
- Cô lập lỗi tải ảnh bìa khi tìm kiếm và giới hạn prefetch tối đa 10 ảnh để
  tránh treo hoặc thiếu bộ nhớ KOReader.
- Không thử lại lần hai một nguồn tìm kiếm đã ném exception; chỉ fallback bỏ
  dấu khi lần đầu trả về danh sách hợp lệ nhưng rỗng.
- Thêm regression/live test: 18 assertion parser, kiểm tra lỗi REST giữa trang,
  live 3.752 bài chính truyện/76 trang, 15/16/6 chương ngoại truyện, tìm kiếm
  4 kết quả không lỗi và tải chương đầu/cuối.

## 3.3.8 (BUILD-1320) - 2026-07-29

### Codex

- Thêm source **Con Đường Bá Chủ** (`conduongbachu.com`) cho danh mục,
  tìm kiếm, mục lục và đọc chương.
- Dùng WordPress REST index (`categories=3`, 100 bài/trang) để lấy toàn bộ
  bài chương; fallback sang `<select class="chapter-selector">` nếu REST API
  bị tắt. Dedupe theo số chương để xử lý dữ liệu website có bài 3059 trùng.
- Hỗ trợ URL slug bất thường như `/3399-vo-de/`, lấy số chương từ tiêu đề
  hiển thị thay vì đoán từ slug. Không tự tạo chương 3509 vì website hiện
  không có bài tương ứng.
- Parser nội dung chỉ giữ các đoạn văn trong `entry-content`, loại phần
  giới thiệu tìm kiếm và metadata trình đọc audio; giữ liên kết chương trước/sau.
- Cứng hóa SearchService: không để source trả dữ liệu sai định dạng làm crash
  vòng lặp tìm kiếm; bỏ qua kết quả thiếu `source_id`/URL/tiêu đề, chặn query
  rỗng và cô lập lỗi từng nguồn.
- Kiểm thử: 17 assertion source, 17 assertion chapter order, search regression,
  35 file Lua compile; live KOReader đạt 76 trang và 3.751 chương duy nhất.

## 3.3.7 (BUILD-1319) - 2026-07-29

### Codex

- Sửa crash khi chạm mép trên để mở menu trong ReaderUI: plugin từng dùng
  `sorting_hint="tools_settings"`, không tồn tại trong
  `reader_menu_order.lua`; chuyển sang menu `tools` hợp lệ và xác minh trực
  tiếp bằng `MenuSorter` của KOReader.
- Thay Sort chỉ đảo các chương của trang hiện tại bằng điều hướng toàn mục lục:
  A-Z nhảy tới trang chứa chương đầu, Z-A nhảy tới trang chứa chương mới nhất.
  Giữ đúng chiều khi chuyển trang và khi đọc tiếp qua ranh giới trang.
- Đánh dấu Akay là nguồn có mục lục giảm dần và thêm module
  `chapter_order.lua` để tính trang biên, chiều hiển thị và trang đọc kế tiếp.
- Nhận diện màn hình khóa VIP theo markup thực tế, không lưu nó thành nội dung
  chương. Tránh nhận nhầm CSS dùng chung là khóa VIP.
- Thêm đăng nhập Akay hợp lệ bằng CSRF + session cookie, lưu tài khoản qua
  CredentialManager và bổ sung mục quản lý tài khoản trong Quản lý nguồn.
  Chương VIP vẫn yêu cầu tài khoản thực sự có quyền.
- Kiểm tra live toàn bộ 6 chương *Ngoại Truyện - Chúa Tể Chi Lộ*: phiên công
  khai chỉ nhận màn hình “Truy cập bị hạn chế”; plugin hiện báo rõ yêu cầu VIP.
- Thêm regression test menu ReaderUI, chapter order, khóa VIP và phiên đăng
  nhập. Tổng kiểm tra mục tiêu: 17 assertion sort, 26 assertion Akay và 34 file
  Lua compile.

## 3.3.6 (BUILD-1318) - 2026-07-29

### Codex

- Tái hiện đúng lỗi B-1317 ở luồng **Truyện đang ra**: các route
  `/danh-sach/truyen-*` của AkayTruyen đã trả `404`, trong khi Browser chỉ
  hiển thị thông báo lỗi tổng quát.
- Thay `getUpdating`, `getHot` và `getCompleted` bằng parser ba mục tương ứng
  trên trang chủ Akay (`section-stories-new`, `section-stories-hot`,
  `section-stories-full`), tránh phụ thuộc route đã bị xóa; kết quả live hiện
  lần lượt có 31, 35 và 4 truyện.
- Bỏ `X-Requested-With: XMLHttpRequest` khỏi request HTML. Akay trả `500` cho
  URL chương khi có header này, còn request trình duyệt thông thường trả `200`.
  Đồng bộ source Lua, JSON bundled, generator output và SPEC.
- Thêm regression assertion bảo đảm request trang chương không gửi header AJAX.
- E2E trong runtime KOReader: Akay “Truyện đang ra”/“Hot”/“Hoàn thành” đọc
  được, *Chung Cực Truyền Kỳ* có 7 trang chương và chương live tải được
  (23.896 ký tự); Storya vẫn đọc được 20 truyện/163 trang để đối chiếu.

## 3.3.5 (BUILD-1317) - 2026-07-29

### Codex

- Xác định nguyên nhân runtime chính: `custom_sources/akaytruyen.json` đóng gói
  trùng ID đã ghi đè module Lua AkayTruyen, khiến bản sửa trong
  `sources/akaytruyen.lua` không được KOReader sử dụng.
- Không cho JSON đóng gói ghi đè nguồn Lua tích hợp; vẫn cho phép JSON do người
  dùng cài trong thư mục dữ liệu chủ động ghi đè.
- Hỗ trợ đầy đủ cả URL chương mới (`/chuong-N-slug`) và URL legacy
  (`/N-slug`, `/slug`) bằng class `chapter-link-mobile`, đồng thời loại link
  hành động/giới thiệu có cùng prefix truyện.
- Dừng và báo lỗi nếu một trang mục lục tải thất bại, rỗng hoặc lặp dữ liệu;
  không còn trả về danh sách thiếu như thể đã thành công.
- Truyền đúng lỗi lấy mục lục từ nguồn lên hai luồng “Tải tất cả các chương” và
  “Tải thành 1 bộ”.
- Đồng bộ rule AkayTruyen trong JSON, Source Generator và tài liệu SPEC.
- Thêm regression test riêng cho AkayTruyen. Kiểm thử live trong môi trường
  KOReader xác nhận *Chung Cực Truyền Kỳ* có 7 trang và đủ 323 chương duy nhất.

## 3.3.4 (BUILD-1316) - 2026-07-28

### Claude Code

- Cải thiện lấy tiêu đề tìm kiếm khi AkayTruyen tách anchor ảnh và anchor tên.
- Lọc anchor chương theo cấu trúc class/nội dung và bổ sung điều hướng chương
  bằng icon chevron.
- Phiên điều tra tiếp theo trong `session01.md` phát hiện URL chương legacy,
  nhưng bản sửa nháp còn nhận quá rộng mọi URL con và chưa phát hiện JSON trùng
  ID ghi đè module Lua.

## 3.3.3 (BUILD-1315) - 2026-07-28

### Claude Code

- Thêm nguồn AkayTruyen, AJAX header `X-Requested-With`, đọc số trang từ
  `jump-input max`, và luồng lấy toàn bộ trang chương.
- Sửa crash menu ReaderUI và các thay đổi gộp sách được ghi nhận trong
  `MEMORY.md`.

## 3.0.1

- Cập nhật parser cho metruyenvn, aztruyen, truyenc, giatocvuongtai, và dualeotruyenfull.
- Thêm cờ force_luasec cho truyenqq để sửa lỗi HTTPS trên Kobo.
- Sửa lỗi crash liên quan đến check nil trong Storage:isFavorite.
- Sửa lỗi Cloudflare 403.

## 1.0.4

- Sửa vòng đời widget để Back, tìm kiếm, lịch sử và phân trang không tạo nhiều màn hình chồng nhau.
- Sửa luồng mở/thoát Reader và chuyển chương để không văng về FileManager.
- Giữ bản chương cũ nếu tải lại thất bại; chỉ thay file sau khi dựng bản mới thành công.
- Chặn ảnh bìa lỗi, kích thước danh sách không hợp lệ và exception khi ghi cài đặt.
- Khôi phục đúng tên miền mặc định sau khi xóa tên miền tùy chỉnh.

## 0.3.0

- Xóa truyện khỏi tủ sẽ cập nhật danh sách và phân trang ngay, không cần thoát ra vào lại.
- Sửa lỗi báo sai `Không thể lưu trạng thái nguồn` khi bật lại TruyenQQ hoặc Dưa Leo.
- Xác nhận gói plugin dùng chung trên KOReader Android, Kindle và Kobo.
- Thêm xem mô tả và thông tin truyện khi giữ một kết quả.
- Thêm tải hàng loạt các chương chưa có trong trang mục lục hiện tại.
- Sửa luồng bật lại nguồn đã tắt và luôn hiển thị trạng thái nguồn ở trang chính.
- Bỏ tích hợp danh mục VBook Extensions.

## 0.2.0

- Thêm nguồn truyện tranh Dưa Leo Truyện.
- Chạm vào từng nguồn để duyệt truyện đã hoàn thành, tìm riêng theo nguồn, lọc thể loại và chuyển trang.
- Thêm tìm kiếm đồng thời nhiều nguồn, chuẩn hóa tiếng Việt và xếp hạng kết quả.
- Hiển thị ảnh bìa, tên truyện và nguồn trong danh sách kết quả.
- Thêm cache ảnh bìa và giao diện kết quả có phân trang.
- Thêm quản lý bật/tắt nguồn và đồng bộ danh mục Darkrai9x/vbook-extensions.
- Bổ sung kiểm thử parser Dưa Leo và thuật toán tìm kiếm.

## 0.1.0

- Thêm nguồn truyện chữ TruyenFull.
- Thêm nguồn manga TruyenQQ.
- Thêm tìm kiếm, tủ truyện và danh sách chương.
- Thêm bộ dựng HTML và CBZ.
- Thêm tích hợp mở tài liệu bằng KOReader.
