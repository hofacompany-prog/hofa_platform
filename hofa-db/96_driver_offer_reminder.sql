-- Cho phép admin chỉnh khoảng cách (giây) giữa các lần PUSH NHẮC LẠI tài xế về đơn mời nhận
-- chưa xác nhận/từ chối (dispatch.remindPendingDriverOffers, server/src/index.js) — cùng ý
-- tưởng order_reminder_interval_seconds (95_order_reminder_interval.sql) phía cửa hàng nhưng
-- tách bảng riêng vì driver_accept_settings vốn đã là nơi cấu hình thanh trượt "Nhận đơn".
ALTER TABLE driver_accept_settings
  ADD COLUMN IF NOT EXISTS offer_reminder_interval_seconds INTEGER NOT NULL DEFAULT 5;
COMMENT ON COLUMN driver_accept_settings.offer_reminder_interval_seconds IS
  'Khoảng cách (giây) giữa các lần gửi lại push mời nhận đơn cho tài xế khi chuyến còn ở trạng thái assigned (chưa xác nhận/từ chối) — lặp tới khi tài xế nhận, từ chối, hoặc hết accept_deadline (tự chuyển tài xế khác), không ghi thêm dòng notifications mới mỗi lần lặp.';

-- Mốc thời gian lần gửi/gửi-lại push mời nhận đơn gần nhất cho 1 chuyến — dùng để tính đủ
-- offer_reminder_interval_seconds mới thật sự gửi lại, xem dispatch.remindPendingDriverOffers.
-- Cùng kiểu orders.order_reminder_last_sent_at (95_order_reminder_interval.sql) đã có cho cửa hàng.
ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS offer_reminder_last_sent_at TIMESTAMPTZ;
COMMENT ON COLUMN deliveries.offer_reminder_last_sent_at IS
  'Lần gần nhất push mời nhận đơn được gửi (lần đầu hoặc nhắc lại) cho chuyến này — dispatch.remindPendingDriverOffers chỉ gửi lại khi đã đủ driver_accept_settings.offer_reminder_interval_seconds kể từ mốc này.';
