-- Lịch sử thông báo đẩy (push notification) admin gửi cho khách hàng — mỗi lần bấm "Gửi
-- thông báo" ở web admin ghi 1 dòng, kèm số thiết bị gửi thành công để admin biết kết quả.
BEGIN;

CREATE TABLE admin_notifications (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title       VARCHAR(150) NOT NULL,
  body        VARCHAR(500) NOT NULL,
  target      VARCHAR(30)  NOT NULL DEFAULT 'all_customers',
  sent_count  INTEGER      NOT NULL DEFAULT 0,
  total_count INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_by  UUID REFERENCES users(id) ON DELETE SET NULL,

  CONSTRAINT admin_notifications_target_valid CHECK (target IN ('all_customers'))
);
COMMENT ON TABLE admin_notifications IS 'Lịch sử thông báo đẩy admin gửi cho khách hàng qua Firebase Cloud Messaging';
COMMENT ON COLUMN admin_notifications.sent_count IS 'Số thiết bị nhận thành công (FCM báo về)';
COMMENT ON COLUMN admin_notifications.total_count IS 'Tổng số thiết bị khách hàng có push_token tại thời điểm gửi';

CREATE INDEX idx_admin_notifications_created ON admin_notifications (created_at DESC);

COMMIT;
