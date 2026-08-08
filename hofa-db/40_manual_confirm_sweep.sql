-- Thanh chạy màu thứ 2 ở màn chi tiết đơn (store app) — chỉ chạy khi chi nhánh TẮT "Tự động
-- nhận đơn" (branches.auto_accept_orders = false). Khác thanh confirm_sweep_seconds (chạy khi
-- BẬT, hết giờ tự XÁC NHẬN): thanh này hết giờ mà cửa hàng chưa trượt thì tự HUỶ đơn + tự đóng
-- cửa chi nhánh — coi như cửa hàng không theo dõi đơn, xử lý hoàn toàn phía CLIENT (store app
-- tự gọi PATCH /orders/:id/status + PATCH /branches/:id/toggle-open ngay trên màn đang mở, xem
-- order_detail_screen.dart), không còn vòng quét nền phía server như trước.
ALTER TABLE auto_accept_settings
  ADD COLUMN IF NOT EXISTS manual_confirm_sweep_seconds INTEGER NOT NULL DEFAULT 300;
COMMENT ON COLUMN auto_accept_settings.manual_confirm_sweep_seconds IS
  'Số giây dải màu chạy trên thanh trượt xác nhận ở màn chi tiết đơn (store app) khi chi nhánh TẮT "Tự động nhận đơn". Hết giờ mà cửa hàng chưa trượt thì tự huỷ đơn và tự đóng cửa chi nhánh (is_open = false) — xử lý phía client, không phải sweep nền server.';

-- Các cột dưới đây (auto_accept_default_minutes, auto_accept_prep_base/increment/max_minutes,
-- manual_confirm_window_minutes) từ hofa-db/37_auto_accept_settings.sql giờ không còn code nào
-- đọc nữa (vòng quét server đã bị xoá — xem server/src/orderOffer.js) — CỐ Ý giữ lại cột, không
-- xoá, để không mất dữ liệu cấu hình cũ; chỉ ngừng hiển thị ở admin và ngừng đọc ở server.
