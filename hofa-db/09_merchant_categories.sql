-- ============================================================================
-- Danh mục riêng của từng cửa hàng, nằm dưới 1 danh mục con của hệ thống.
-- Chạy 1 lần trên Supabase SQL Editor (đã có sẵn bảng categories/products từ 01_schema.sql).
-- ============================================================================

CREATE TABLE merchant_categories (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id UUID NOT NULL REFERENCES merchants(id)  ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE, -- danh mục con hệ thống
  name        VARCHAR(150) NOT NULL,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE merchant_categories IS 'Danh mục riêng của 1 cửa hàng, nằm dưới 1 danh mục con hệ thống — khách chỉ thấy danh mục này khi xem cửa hàng';

CREATE INDEX idx_merchant_categories_merchant ON merchant_categories (merchant_id) WHERE is_active;
CREATE INDEX idx_merchant_categories_category ON merchant_categories (category_id) WHERE is_active;

ALTER TABLE products ADD COLUMN merchant_category_id UUID REFERENCES merchant_categories(id) ON DELETE SET NULL;
CREATE INDEX idx_products_merchant_category ON products (merchant_category_id) WHERE deleted_at IS NULL;
