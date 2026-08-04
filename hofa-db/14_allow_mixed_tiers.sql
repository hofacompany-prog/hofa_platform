-- ============================================================================
-- MIGRATION 14 — Cho phép 1 biến thể có CẢ bậc giá sỉ lẫn bậc đặt trước cùng lúc
--
-- Trước giờ web cửa hàng chặn UI không cho thêm bậc loại này nếu biến thể đã có bậc
-- loại kia — bỏ chặn đó (phía app). Ràng buộc UNIQUE (variant_id, min_quantity) ở DB vô
-- tình cũng chặn luôn việc thêm 2 bậc CÙNG min_quantity nhưng KHÁC loại (vd giá sỉ từ 10
-- và đặt trước từ 10) — đổi lại UNIQUE (variant_id, min_quantity, min_days_per_week) để
-- chỉ cấm trùng khi CÙNG loại.
--
-- Chạy 1 lần trên Supabase SQL Editor. Đã gộp vào hofa-db/01_schema.sql cho lần dựng DB
-- mới từ đầu.
-- ============================================================================

BEGIN;

ALTER TABLE wholesale_tiers DROP CONSTRAINT wholesale_tiers_variant_id_min_quantity_key;
ALTER TABLE wholesale_tiers ADD CONSTRAINT wholesale_tiers_variant_id_min_quantity_min_days_per_week_key
  UNIQUE (variant_id, min_quantity, min_days_per_week);

COMMIT;
