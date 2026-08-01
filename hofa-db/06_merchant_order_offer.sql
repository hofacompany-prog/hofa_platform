-- ============================================================================
-- Hỗ trợ push thông báo đơn mới + xác nhận có thời hạn cho app cửa hàng (giống
-- luồng offer/accept của app tài xế): chi nhánh bật "tự động nhận đơn" thì đơn
-- mới tự chuyển sang 'confirmed', chi nhánh thường thì cửa hàng phải bấm "Nhận
-- đơn" trong 1 khung giờ ngắn — quá hạn thì đơn tự huỷ.
--
-- Chạy file này 1 lần trong Supabase SQL Editor (đã đồng bộ vào 01_schema.sql
-- để những lần cài đặt mới không cần chạy lại file này).
-- ============================================================================

ALTER TABLE branches
  ADD COLUMN IF NOT EXISTS auto_accept_orders BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN branches.auto_accept_orders IS 'true = hệ thống tự xác nhận đơn mới cho chi nhánh này, không cần nhân viên bấm nhận';

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS accept_deadline TIMESTAMPTZ;
COMMENT ON COLUMN orders.accept_deadline IS 'Hạn cửa hàng xác nhận đơn (áp dụng khi branches.auto_accept_orders = false)';
