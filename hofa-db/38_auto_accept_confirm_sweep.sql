-- Thời gian (giây) dải màu chạy trên thanh trượt xác nhận thời gian chuẩn bị ở màn chi tiết
-- đơn (store app, order_detail_screen.dart) — admin cấu hình ở web admin, mục "Thông số", cùng
-- bảng với các tham số "Tự động nhận đơn" khác dù áp dụng cho MỌI đơn "placed" (không phụ
-- thuộc branches.auto_accept_orders).
ALTER TABLE auto_accept_settings
  ADD COLUMN IF NOT EXISTS confirm_sweep_seconds INTEGER NOT NULL DEFAULT 10;
COMMENT ON COLUMN auto_accept_settings.confirm_sweep_seconds IS
  'Số giây dải màu chạy trên thanh trượt xác nhận thời gian chuẩn bị ở màn chi tiết đơn (store app). Hết giờ mà cửa hàng chưa trượt thì tự chốt số phút đang hiện trên bộ đếm +/- và chuyển đơn sang "confirmed".';
