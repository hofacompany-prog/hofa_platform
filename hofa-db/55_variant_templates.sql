-- Thư viện biến thể mẫu của 1 cửa hàng — tạo 1 lần (tên + giá + bậc giá), rồi chọn từ đây
-- lúc thêm biến thể cho 1 sản phẩm thay vì gõ lại từ đầu mỗi lần. Cấu trúc giống hệt cặp
-- product_variants/wholesale_tiers (chỉ đổi product_id -> merchant_id) để dễ copy 1-1 sang
-- product_variants/wholesale_tiers thật khi merchant áp dụng mẫu vào 1 sản phẩm — KHÔNG
-- share 1 row như topping_groups, vì giá 1 biến thể (vd "500g") thường khác nhau giữa các
-- sản phẩm dù cùng tên/cấu trúc bậc giá. Sửa mẫu sau này không ảnh hưởng sản phẩm đã tạo
-- từ mẫu (đã copy xong là tách biệt hoàn toàn).
CREATE TABLE variant_templates (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id     UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  name            VARCHAR(150) NOT NULL,
  price           INTEGER NOT NULL,
  compare_price   INTEGER,
  cost_price      INTEGER,
  wholesale_price INTEGER,
  sort_order      INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT variant_templates_price_positive CHECK (price >= 0),
  CONSTRAINT variant_templates_compare_gte    CHECK (compare_price IS NULL OR compare_price >= price)
);
COMMENT ON TABLE variant_templates IS 'Thư viện biến thể mẫu của 1 cửa hàng — copy thành product_variants khi áp dụng vào 1 sản phẩm, sửa mẫu không ảnh hưởng sản phẩm đã tạo từ mẫu';

CREATE INDEX idx_variant_templates_merchant ON variant_templates (merchant_id);

-- Bậc giá của 1 biến thể mẫu — cấu trúc giống hệt wholesale_tiers (chỉ đổi variant_id ->
-- template_id), copy sang wholesale_tiers thật cùng lúc với product_variants.
CREATE TABLE variant_template_tiers (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  template_id        UUID NOT NULL REFERENCES variant_templates(id) ON DELETE CASCADE,
  min_quantity       INTEGER NOT NULL,
  max_quantity       INTEGER,
  unit_price         INTEGER NOT NULL,
  min_days_per_week  INTEGER NOT NULL DEFAULT 0,
  unit_price_days    INTEGER,
  unit_price_both    INTEGER,
  min_order_quantity INTEGER,
  requires_deposit   BOOLEAN NOT NULL DEFAULT false,
  deposit_percent    NUMERIC(5,2) DEFAULT 0,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE variant_template_tiers IS 'Bậc giá của 1 biến thể mẫu — copy sang wholesale_tiers thật khi áp dụng mẫu vào 1 sản phẩm';

CREATE INDEX idx_variant_template_tiers_template ON variant_template_tiers (template_id);
