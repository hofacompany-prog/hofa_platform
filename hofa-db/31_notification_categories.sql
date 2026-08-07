-- Danh mục thông báo — cho phép app lọc theo tab (Tất cả/Đơn hàng/Khuyến mãi/Quảng cáo...)
-- thay vì 1 danh sách chung. Thông báo hệ thống về đơn/chuyến giao (qua push.sendPushToUser)
-- luôn tự gắn 'order'; thông báo admin gửi tay (màn "Thông báo" ở web admin) do admin tự
-- chọn danh mục lúc soạn — mặc định 'system' nếu không chọn.
BEGIN;

ALTER TABLE notifications ADD COLUMN category VARCHAR(20) NOT NULL DEFAULT 'system';
ALTER TABLE notifications ADD CONSTRAINT notifications_category_valid
  CHECK (category IN ('order', 'promotion', 'ad', 'system'));
COMMENT ON COLUMN notifications.category IS
  'Danh mục hiển thị theo tab trong app — order (đơn hàng/chuyến giao, tự động gắn), promotion
  (khuyến mãi), ad (quảng cáo), system (khác) — 2 cái sau admin tự chọn lúc gửi tay';
CREATE INDEX idx_notifications_user_category ON notifications (user_id, category, created_at DESC);

ALTER TABLE admin_notifications ADD COLUMN category VARCHAR(20) NOT NULL DEFAULT 'system';
ALTER TABLE admin_notifications ADD CONSTRAINT admin_notifications_category_valid
  CHECK (category IN ('order', 'promotion', 'ad', 'system'));
COMMENT ON COLUMN admin_notifications.category IS
  'Danh mục admin chọn lúc soạn — ghi lại để xem lại lịch sử, xem notifications.category';

COMMIT;
