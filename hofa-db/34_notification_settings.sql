-- Cấu hình chung cho hộp thư thông báo (bảng notifications) — chỉ giữ 1 dòng đang áp dụng
-- (dòng mới nhất theo updated_at), cùng kiểu với shipping_fee_settings/order_settings.
-- ttl_hours: số giờ 1 thông báo được giữ trong hộp thư trước khi bị sweep tự xoá (xem
-- server/src/index.js, sweepOldNotifications) — NULL nghĩa là không tự xoá.
CREATE TABLE IF NOT EXISTS notification_settings (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ttl_hours  INTEGER,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

  CONSTRAINT notification_settings_ttl_valid CHECK (ttl_hours IS NULL OR ttl_hours > 0)
);
COMMENT ON TABLE notification_settings IS
  'Cấu hình hộp thư thông báo toàn sàn — chỉ giữ 1 dòng (dòng mới nhất theo updated_at), admin sửa qua GET/PATCH /notification-settings';

INSERT INTO notification_settings (ttl_hours)
SELECT NULL
WHERE NOT EXISTS (SELECT 1 FROM notification_settings);
