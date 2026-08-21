-- Cho phép admin chỉnh khoảng cách (giây) giữa các lần PUSH NHẮC LẠI cửa hàng về đơn mới chưa
-- xác nhận (orderOffer.remindUnconfirmedOrders, server/src/index.js) — trước đây hard-code 20s
-- trong code, giờ đọc từ đây, cùng bảng auto_accept_settings (chỉ giữ 1 dòng đang áp dụng) với
-- confirm_sweep_seconds/manual_confirm_sweep_seconds đã có.
ALTER TABLE auto_accept_settings
  ADD COLUMN IF NOT EXISTS order_reminder_interval_seconds INTEGER NOT NULL DEFAULT 20;
COMMENT ON COLUMN auto_accept_settings.order_reminder_interval_seconds IS
  'Khoảng cách (giây) giữa các lần gửi lại push "Đơn hàng mới!" cho cửa hàng khi đơn còn ở trạng thái placed (chưa xác nhận) — lặp tới khi cửa hàng xác nhận, không ghi thêm dòng notifications mới mỗi lần lặp.';

-- Mốc thời gian lần gửi/gửi-lại push "Đơn hàng mới!" gần nhất cho 1 đơn — dùng để tính đủ
-- order_reminder_interval_seconds mới thật sự gửi lại, xem orderOffer.remindUnconfirmedOrders.
-- Cùng kiểu driver_search_last_attempt_at (05_driver_dispatch.sql) đã có sẵn cho việc quét tài xế.
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS order_reminder_last_sent_at TIMESTAMPTZ;
COMMENT ON COLUMN orders.order_reminder_last_sent_at IS
  'Lần gần nhất push "Đơn hàng mới!" được gửi (lần đầu hoặc nhắc lại) cho đơn này — orderOffer.remindUnconfirmedOrders chỉ gửi lại khi đã đủ order_reminder_interval_seconds kể từ mốc này.';
