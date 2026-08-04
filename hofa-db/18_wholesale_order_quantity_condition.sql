-- Thêm điều kiện THAY THẾ cho bậc giá sỉ (min_days_per_week = 0): nếu tổng số lượng CẢ
-- đơn (gộp mọi sản phẩm) đạt min_order_quantity, sản phẩm vẫn được giá bậc này dù số
-- lượng riêng sản phẩm đó chưa đạt min_quantity. Ví dụ: bậc yêu cầu mua 10 mới có giá sỉ,
-- nhưng đặt min_order_quantity = 5 — khách mua 3 sản phẩm này nhưng cả đơn có 5 sản phẩm
-- (bất kỳ) thì vẫn được giá sỉ của bậc đó.
BEGIN;

ALTER TABLE wholesale_tiers ADD COLUMN min_order_quantity INTEGER;

ALTER TABLE wholesale_tiers ADD CONSTRAINT tiers_min_order_quantity_valid
  CHECK (min_order_quantity IS NULL OR min_order_quantity > 0);

COMMENT ON COLUMN wholesale_tiers.min_order_quantity IS
  'Chỉ áp dụng cho bậc giá sỉ (min_days_per_week = 0) — điều kiện THAY THẾ theo tổng số
  lượng cả đơn (mọi sản phẩm cộng lại), đạt 1 trong 2 (số lượng riêng món HOẶC số lượng
  cả đơn) là được giá bậc này';

COMMIT;
