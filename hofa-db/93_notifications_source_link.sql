-- ============================================================================
-- MIGRATION 93 — Liên kết hộp thư người nhận (notifications) về đúng đợt gửi thủ công của
-- admin (admin_notifications) — để xoá 1 dòng ở "Lịch sử đã gửi" (web admin, tab Gửi thông
-- báo) thì thông báo TRONG HỘP THƯ CỦA MỌI NGƯỜI NHẬN tương ứng cũng tự mất theo (ON DELETE
-- CASCADE), thay vì chỉ mất dòng log mà thông báo vẫn còn nằm lì trên máy khách/cửa hàng/tài
-- xế. NULL với mọi thông báo hệ thống khác (đơn hàng, báo cáo sự cố, đổi trạng thái...) —
-- những luồng đó không đi qua admin_notifications nên không có gì để trỏ về.
-- ============================================================================

ALTER TABLE notifications
  ADD COLUMN source_notification_id UUID REFERENCES admin_notifications(id) ON DELETE CASCADE;
COMMENT ON COLUMN notifications.source_notification_id IS
  'Trỏ về admin_notifications.id nếu dòng này sinh ra từ 1 đợt gửi thủ công của admin — xoá đợt
   gửi đó (DELETE /admin/notifications/:id) sẽ CASCADE xoá luôn dòng hộp thư này. NULL với
   thông báo hệ thống (đơn hàng, báo cáo sự cố...) không liên quan tới admin_notifications.';

CREATE INDEX idx_notifications_source ON notifications (source_notification_id)
  WHERE source_notification_id IS NOT NULL;
