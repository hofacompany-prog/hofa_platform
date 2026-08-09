-- Icon tabbar tuỳ chỉnh cho cả 4 app (admin/customer/store/driver) — admin chọn icon từ thư
-- viện Lucide (bundled sẵn trong app admin, xem hofa_admin_app/assets/lucide_icons/) rồi tải
-- lên Cloudinary, mỗi app khác chỉ đọc URL đã lưu ở đây lúc khởi động (GET /nav-icons, công
-- khai, không cần đăng nhập), không tự gọi thư viện ngoài. Không có dòng cho 1 tab nào đó thì
-- app tự dùng icon Material mặc định có sẵn trong code — bảng này chỉ override, không phải
-- nguồn bắt buộc, nên xoá sạch bảng vẫn không làm hỏng điều hướng của app nào.
CREATE TABLE IF NOT EXISTS nav_tab_icons (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  app         TEXT NOT NULL CHECK (app IN ('admin','customer','store','driver')),
  tab_key     TEXT NOT NULL,
  icon_url    TEXT NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID REFERENCES users(id) ON DELETE SET NULL,
  UNIQUE (app, tab_key)
);
COMMENT ON TABLE nav_tab_icons IS
  'Icon tuỳ chỉnh cho từng tab điều hướng của 4 app — icon_url là ảnh PNG đã qua Cloudinary
   (rasterize từ SVG gốc trong thư viện Lucide), tô màu động ở client bằng
   colorFilter/colorBlendMode (srcIn) nên chỉ cần 1 ảnh/tab, không cần 2 bản selected/unselected
   như icon Material.';
COMMENT ON COLUMN nav_tab_icons.tab_key IS
  'Khoá ổn định cho 1 tab, độc lập với route path (route có thể đổi) — danh sách khoá hợp lệ cho
   từng app nằm ở hofa_admin_app/lib/core/nav_tab_slots.dart.';
