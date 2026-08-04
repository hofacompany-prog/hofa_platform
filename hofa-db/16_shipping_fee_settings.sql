-- ============================================================================
-- MIGRATION 16 — Cấu hình phí ship toàn sàn (web admin, mục "Phí ship")
--
-- Thêm bảng shipping_fee_settings — chỉ giữ 1 dòng đang áp dụng (dòng mới nhất theo
-- updated_at). Công thức: phí ship = base_fee (cho base_distance_km đầu) + per_km_fee ×
-- (số km vượt base_distance_km, nếu > 0), làm tròn theo round_to, không vượt quá max_fee
-- (nếu có), và bằng 0 nếu tổng đơn hàng ≥ free_ship_threshold (nếu có). Cùng kiểu công
-- thức base+per_km đang dùng để tính phí trả tài xế (BASE_FEE/PER_KM_FEE trong
-- server/src/dispatch.js) cho nhất quán.
--
-- Đây là bước 1 (cấu hình) — CHƯA nối vào create_order()/checkout, đơn hàng vẫn đang
-- luôn miễn phí ship (delivery_fee gửi cứng = 0 từ app khách) như trước, chờ làm bước
-- tính phí thật ở lần sau.
--
-- Chạy 1 lần trên Supabase SQL Editor. Đã gộp vào hofa-db/01_schema.sql cho lần dựng DB
-- mới từ đầu.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS shipping_fee_settings (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  is_active           BOOLEAN NOT NULL DEFAULT true,
  base_fee            INTEGER NOT NULL DEFAULT 15000,
  base_distance_km    NUMERIC(6,2) NOT NULL DEFAULT 2,
  per_km_fee          INTEGER NOT NULL DEFAULT 4000,
  free_ship_threshold INTEGER,
  max_fee             INTEGER,
  round_to            INTEGER NOT NULL DEFAULT 500,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by          UUID REFERENCES users(id) ON DELETE SET NULL,

  CONSTRAINT shipping_fee_base_valid      CHECK (base_fee >= 0),
  CONSTRAINT shipping_fee_distance_valid  CHECK (base_distance_km >= 0),
  CONSTRAINT shipping_fee_per_km_valid    CHECK (per_km_fee >= 0),
  CONSTRAINT shipping_fee_threshold_valid CHECK (free_ship_threshold IS NULL OR free_ship_threshold >= 0),
  CONSTRAINT shipping_fee_max_valid       CHECK (max_fee IS NULL OR max_fee >= 0),
  CONSTRAINT shipping_fee_round_valid     CHECK (round_to > 0)
);
COMMENT ON TABLE shipping_fee_settings IS
  'Cấu hình phí ship toàn sàn — chỉ giữ 1 dòng (dòng mới nhất theo updated_at) đang áp dụng, admin sửa qua GET/PATCH /shipping-fee-settings';

INSERT INTO shipping_fee_settings (is_active, base_fee, base_distance_km, per_km_fee)
SELECT true, 15000, 2, 4000
WHERE NOT EXISTS (SELECT 1 FROM shipping_fee_settings);

COMMIT;
