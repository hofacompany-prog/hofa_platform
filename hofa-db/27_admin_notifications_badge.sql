-- Cho phép admin chọn có cộng số vào badge biểu tượng PWA (Badging API, chỉ có ý nghĩa khi
-- người dùng đã "Thêm vào màn hình chính") khi gửi thông báo thủ công ở màn Thông báo — mặc
-- định KHÔNG cộng, vì badge nên dành cho thứ cần hành động chứ không phải mọi thông báo chung
-- chung. Thông báo tự động về đơn hàng (order_status_changed, offer cho cửa hàng/tài xế...)
-- không đi qua bảng này, luôn cộng badge mặc định — xem server/src/push.js.
BEGIN;

ALTER TABLE admin_notifications ADD COLUMN show_badge BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN admin_notifications.show_badge IS
  'true nếu thông báo này có cộng số vào badge biểu tượng PWA của người nhận (Badging API)';

COMMIT;
