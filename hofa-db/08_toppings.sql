-- ============================================================================
-- Topping (tuỳ chọn thêm) cho sản phẩm — vd trà sữa: trân châu, thạch, pudding...
-- Mỗi sản phẩm có 0..N nhóm topping (vd "Chọn topping", "Độ ngọt"); mỗi nhóm tự
-- chọn được bắt buộc hay không (is_required) và cho chọn nhiều mục hay chỉ 1
-- (allow_multiple). Từng lựa chọn trong nhóm có giá cộng thêm riêng.
--
-- Chạy file này 1 lần trong Supabase SQL Editor (đã đồng bộ vào 01_schema.sql
-- để những lần cài đặt mới không cần chạy lại file này).
-- ============================================================================

CREATE TABLE IF NOT EXISTS product_topping_groups (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id     UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  name           VARCHAR(150) NOT NULL,          -- VD: 'Chọn topping', 'Độ ngọt', 'Size'
  is_required    BOOLEAN NOT NULL DEFAULT false, -- bắt buộc chọn ít nhất 1 mục khi đặt hàng
  allow_multiple BOOLEAN NOT NULL DEFAULT false, -- true = chọn nhiều mục cùng lúc, false = chỉ 1
  sort_order     INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE product_topping_groups IS 'Nhóm tuỳ chọn thêm của 1 sản phẩm (topping, size, độ ngọt...)';

CREATE INDEX IF NOT EXISTS idx_topping_groups_product ON product_topping_groups (product_id);

CREATE TABLE IF NOT EXISTS product_toppings (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_id   UUID NOT NULL REFERENCES product_topping_groups(id) ON DELETE CASCADE,
  name       VARCHAR(150) NOT NULL,       -- VD: 'Trân châu đen', 'Ít đường'
  price      INTEGER NOT NULL DEFAULT 0,  -- giá cộng thêm (VNĐ), 0 = miễn phí
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT product_toppings_price_nonnegative CHECK (price >= 0)
);
COMMENT ON TABLE product_toppings IS 'Từng lựa chọn cụ thể trong 1 nhóm topping, có giá cộng thêm riêng';

CREATE INDEX IF NOT EXISTS idx_toppings_group ON product_toppings (group_id);
