-- Tham số điều khiển hành vi công tắc "Tự động nhận đơn" (branches.auto_accept_orders) — áp
-- dụng cho TOÀN HỆ THỐNG (không phải theo từng cửa hàng), admin cấu hình ở web admin, mục
-- "Thông số". Chỉ giữ 1 dòng đang áp dụng (dòng mới nhất theo updated_at), cùng kiểu với
-- shipping_fee_settings/order_settings/notification_settings.
CREATE TABLE IF NOT EXISTS auto_accept_settings (
  id                                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auto_accept_default_minutes         INTEGER NOT NULL DEFAULT 8,
  auto_accept_prep_base_minutes       INTEGER NOT NULL DEFAULT 10,
  auto_accept_prep_increment_minutes  INTEGER NOT NULL DEFAULT 2,
  auto_accept_prep_max_minutes        INTEGER NOT NULL DEFAULT 30,
  manual_confirm_window_minutes       INTEGER NOT NULL DEFAULT 5,
  updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by                          UUID REFERENCES users(id) ON DELETE SET NULL
);
COMMENT ON TABLE auto_accept_settings IS
  'Cấu hình toàn sàn cho công tắc "Tự động nhận đơn" — chỉ giữ 1 dòng, admin sửa qua GET/PATCH /auto-accept-settings';
COMMENT ON COLUMN auto_accept_settings.auto_accept_default_minutes IS
  'Bật "Tự động nhận đơn": số phút mặc định cửa hàng có để trượt xác nhận trước khi hệ thống tự nhận đơn hộ (không vượt quá trần theo số món, xem auto_accept_prep_*).';
COMMENT ON COLUMN auto_accept_settings.auto_accept_prep_base_minutes IS
  'Trần thời gian chuẩn bị (phút) khi đơn chỉ có 1 món — dùng để tính trần cho auto_accept_default_minutes và giới hạn nút +/- ở màn nhận đơn.';
COMMENT ON COLUMN auto_accept_settings.auto_accept_prep_increment_minutes IS
  'Số phút cộng thêm vào trần cho mỗi món tiếp theo (từ món thứ 2 trở đi) trong 1 đơn.';
COMMENT ON COLUMN auto_accept_settings.auto_accept_prep_max_minutes IS
  'Trần tối đa toàn đơn (phút), bất kể đơn có bao nhiêu món.';
COMMENT ON COLUMN auto_accept_settings.manual_confirm_window_minutes IS
  'Tắt "Tự động nhận đơn": số phút cửa hàng có để xác nhận thủ công trước khi đơn tự huỷ và chi nhánh tự chuyển sang "Tạm đóng cửa".';

INSERT INTO auto_accept_settings (auto_accept_default_minutes)
SELECT 8 WHERE NOT EXISTS (SELECT 1 FROM auto_accept_settings);
