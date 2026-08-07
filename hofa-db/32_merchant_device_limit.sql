-- Giới hạn số thiết bị (điện thoại/trình duyệt) được đăng nhập nhận thông báo cùng lúc cho
-- 1 cửa hàng — tính chung chủ + toàn bộ nhân viên. Admin cấu hình ở web admin (màn chi tiết
-- cửa hàng). Vượt quá thì phải gỡ bớt thiết bị cũ nhất mới đăng nhập thêm thiết bị mới được
-- (server/src/routes/users.js POST /devices) — tránh nhiều thiết bị cùng nhận trùng thông báo
-- đơn hàng, hoặc lẫn lộn giữa các thiết bị test cũ còn sót lại.
ALTER TABLE merchants ADD COLUMN max_devices INTEGER NOT NULL DEFAULT 1 CHECK (max_devices >= 1);
COMMENT ON COLUMN merchants.max_devices IS
  'Số thiết bị tối đa được đăng nhập/nhận thông báo cùng lúc cho cửa hàng này (tính chung chủ + nhân viên)';
