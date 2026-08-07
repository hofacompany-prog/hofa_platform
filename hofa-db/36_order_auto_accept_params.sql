-- Tham số điều khiển hành vi công tắc "Tự động nhận đơn" (branches.auto_accept_orders) — cấu
-- hình ở tab "Thông số" trong store app, áp dụng cho toàn bộ chi nhánh của 1 cửa hàng.
ALTER TABLE merchants
  ADD COLUMN auto_accept_default_minutes INTEGER NOT NULL DEFAULT 8,
  ADD COLUMN auto_accept_prep_base_minutes INTEGER NOT NULL DEFAULT 10,
  ADD COLUMN auto_accept_prep_increment_minutes INTEGER NOT NULL DEFAULT 2,
  ADD COLUMN auto_accept_prep_max_minutes INTEGER NOT NULL DEFAULT 30,
  ADD COLUMN manual_confirm_window_minutes INTEGER NOT NULL DEFAULT 5;

COMMENT ON COLUMN merchants.auto_accept_default_minutes IS
  'Bật "Tự động nhận đơn": số phút mặc định cửa hàng có để trượt xác nhận trước khi hệ thống tự nhận đơn hộ (không vượt quá trần theo số món, xem auto_accept_prep_*).';
COMMENT ON COLUMN merchants.auto_accept_prep_base_minutes IS
  'Trần thời gian chuẩn bị (phút) khi đơn chỉ có 1 món — dùng để tính trần cho auto_accept_default_minutes và giới hạn nút +/- ở màn nhận đơn.';
COMMENT ON COLUMN merchants.auto_accept_prep_increment_minutes IS
  'Số phút cộng thêm vào trần cho mỗi món tiếp theo (từ món thứ 2 trở đi) trong 1 đơn.';
COMMENT ON COLUMN merchants.auto_accept_prep_max_minutes IS
  'Trần tối đa toàn đơn (phút), bất kể đơn có bao nhiêu món.';
COMMENT ON COLUMN merchants.manual_confirm_window_minutes IS
  'Tắt "Tự động nhận đơn": số phút cửa hàng có để xác nhận thủ công trước khi đơn tự huỷ và chi nhánh tự chuyển sang "Tạm đóng cửa".';

ALTER TABLE orders ADD COLUMN late_minutes INTEGER;
COMMENT ON COLUMN orders.late_minutes IS
  'Số phút cửa hàng làm trễ so với estimated_prep_minutes, tính khi đơn chuyển sang ready_for_pickup. NULL = đúng giờ hoặc chưa tới bước đó.';
