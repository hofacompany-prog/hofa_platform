-- Cho phép admin chọn NHÓM đối tượng trước (khách hàng / cửa hàng / tài xế), sau đó mới
-- chọn "tất cả" hay "cụ thể" trong nhóm đó — trước đây chỉ gửi được cho khách hàng.
BEGIN;

ALTER TABLE admin_notifications ADD COLUMN audience_type VARCHAR(20) NOT NULL DEFAULT 'customer';
UPDATE admin_notifications SET audience_type = 'customer';
ALTER TABLE admin_notifications
  ADD CONSTRAINT admin_notifications_audience_type_valid CHECK (audience_type IN ('customer', 'merchant', 'driver'));

-- target trước đây gắn chết với khách hàng ('all_customers'/'specific_users') — đổi thành
-- chung cho mọi nhóm ('all'/'specific'), ý nghĩa "nhóm nào" đã tách sang audience_type.
UPDATE admin_notifications SET target = 'all' WHERE target = 'all_customers';
UPDATE admin_notifications SET target = 'specific' WHERE target = 'specific_users';
ALTER TABLE admin_notifications DROP CONSTRAINT admin_notifications_target_valid;
ALTER TABLE admin_notifications ADD CONSTRAINT admin_notifications_target_valid CHECK (target IN ('all', 'specific'));

-- Cửa hàng cụ thể được chọn khi audience_type=merchant, target=specific — chỉ để hiển thị
-- lại lịch sử (thông báo thật gửi tới toàn bộ chủ + nhân viên các cửa hàng này, ghi trong
-- admin_notification_recipients như các nhóm khác).
CREATE TABLE admin_notification_target_merchants (
  notification_id UUID NOT NULL REFERENCES admin_notifications(id) ON DELETE CASCADE,
  merchant_id      UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  PRIMARY KEY (notification_id, merchant_id)
);
COMMENT ON TABLE admin_notification_target_merchants IS
  'Cửa hàng cụ thể được chọn khi admin_notifications.audience_type=merchant và target=specific — chỉ để tra lại lịch sử';

COMMIT;
