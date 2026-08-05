-- Cho phép admin gửi thông báo cho 1 nhóm khách hàng cụ thể (target='specific_users'),
-- không chỉ "Tất cả khách hàng". Ghi lại danh sách người nhận cụ thể để xem lại lịch sử.
BEGIN;

ALTER TABLE admin_notifications
  DROP CONSTRAINT admin_notifications_target_valid,
  ADD CONSTRAINT admin_notifications_target_valid CHECK (target IN ('all_customers', 'specific_users'));

CREATE TABLE admin_notification_recipients (
  notification_id UUID NOT NULL REFERENCES admin_notifications(id) ON DELETE CASCADE,
  user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (notification_id, user_id)
);
COMMENT ON TABLE admin_notification_recipients IS
  'Danh sách người nhận cụ thể khi admin_notifications.target = specific_users — chỉ dùng để tra lại lịch sử, không dùng khi target = all_customers';

COMMIT;
