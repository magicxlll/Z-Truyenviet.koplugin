# Changelog

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
