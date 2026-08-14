-- ============================================================================
-- MIGRATION 82 — Trước giờ khi không tìm được tài xế nào (offerToNearestDriver trả về null),
-- server chỉ log cảnh báo rồi dừng hẳn — đơn kẹt vô thời hạn ở ready_for_pickup, không ai biết.
-- Thêm cơ chế tự quét lại định kỳ, sau N lần vẫn không có ai thì báo admin quyết định (huỷ đơn
-- hay quét tiếp) — tất cả tham số (bao lâu quét lại 1 lần, quét mấy lần thì báo) admin tự cấu
-- hình được, không hardcode.
-- ============================================================================

CREATE TABLE driver_dispatch_settings (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  rescan_interval_seconds  INTEGER NOT NULL DEFAULT 60 CHECK (rescan_interval_seconds > 0),
  max_rescan_attempts      INTEGER NOT NULL DEFAULT 10 CHECK (max_rescan_attempts > 0),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by               UUID REFERENCES users(id)
);
COMMENT ON TABLE driver_dispatch_settings IS
  'Cấu hình quét tìm tài xế khi đơn chưa có ai nhận (offerToNearestDriver không tìm được ai) —
   quét lại mỗi rescan_interval_seconds giây, sau max_rescan_attempts lần liên tiếp không tìm
   được thì báo admin (notifyAdmins) quyết định huỷ đơn hay quét tiếp (reset về 0 lần, quét tiếp
   theo đúng chu kỳ này, tự báo lại khi hết lượt lần nữa).';

ALTER TABLE orders ADD COLUMN driver_search_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN driver_search_last_attempt_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN driver_search_alerted_at TIMESTAMPTZ;
COMMENT ON COLUMN orders.driver_search_attempts IS
  'Số lần đã quét tìm tài xế mà không thấy ai — reset về 0 khi gán được tài xế hoặc admin chọn "Quét tiếp"';
COMMENT ON COLUMN orders.driver_search_alerted_at IS
  'Đã báo admin và đang chờ quyết định (huỷ đơn/quét tiếp) — sweepDriverSearch bỏ qua đơn này
   cho tới khi admin phản hồi (xem POST /admin/orders/:id/driver-search/continue)';
