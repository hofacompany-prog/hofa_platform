-- ============================================================================
-- MIGRATION 91 — Bắt buộc tài xế đứng gần cửa hàng lúc xác nhận "Đã lấy hàng" cho đơn mua hộ
--
-- Đơn mua hộ (buy_on_behalf) không có ai ở cửa hàng xác nhận hộ tài xế đã lấy hàng thật (khác
-- đơn thường: OTP đọc từ nhân viên cửa hàng) — chỉ dựa vào ảnh tài xế tự chụp, dễ chụp khống từ
-- xa. Thêm bước: lúc xác nhận "Đã lấy hàng", app tài xế gửi kèm toạ độ hiện tại, server so với
-- toạ độ chi nhánh (branches.latitude/longitude), cách nhau quá max_distance_meters thì chặn —
-- xem server/src/routes/deliveries.js (PATCH /deliveries/:id/status).
-- ============================================================================

CREATE TABLE IF NOT EXISTS pickup_proximity_settings (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  max_distance_meters INTEGER NOT NULL DEFAULT 100 CHECK (max_distance_meters > 0),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by          UUID REFERENCES users(id) ON DELETE SET NULL
);
COMMENT ON TABLE pickup_proximity_settings IS
  'Chỉ giữ 1 dòng đang áp dụng (dòng mới nhất theo updated_at, cùng kiểu với auto_accept_settings/
   driver_dispatch_settings) — bán kính tối đa (mét) giữa tài xế và chi nhánh lúc xác nhận "Đã lấy
   hàng" cho đơn mua hộ, admin cấu hình qua GET/PATCH /pickup-proximity-settings.';

INSERT INTO pickup_proximity_settings (max_distance_meters)
SELECT 100 WHERE NOT EXISTS (SELECT 1 FROM pickup_proximity_settings);
