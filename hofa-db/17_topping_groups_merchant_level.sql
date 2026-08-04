-- Đưa nhóm topping từ gắn cứng với 1 sản phẩm thành thư viện dùng chung của cả cửa hàng —
-- cửa hàng tạo 1 nhóm topping 1 lần rồi gắn vào nhiều sản phẩm khác nhau, không phải tạo
-- lại từ đầu mỗi lần thêm sản phẩm mới.
BEGIN;

ALTER TABLE product_topping_groups RENAME TO topping_groups;

ALTER TABLE topping_groups ADD COLUMN merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE;

-- Trước migration này 1 nhóm chỉ thuộc đúng 1 sản phẩm — suy ra merchant_id từ sản phẩm đó.
UPDATE topping_groups tg
   SET merchant_id = p.merchant_id
  FROM products p
 WHERE tg.product_id = p.id;

ALTER TABLE topping_groups ALTER COLUMN merchant_id SET NOT NULL;

-- Bảng nối nhiều-nhiều sản phẩm <-> nhóm topping (giống pattern product_categories).
CREATE TABLE product_topping_group_links (
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  group_id   UUID NOT NULL REFERENCES topping_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (product_id, group_id)
);
COMMENT ON TABLE product_topping_group_links IS 'Nối sản phẩm với nhóm topping. 1 sản phẩm dùng nhiều nhóm, 1 nhóm dùng cho nhiều sản phẩm';

-- Giữ lại đúng liên kết 1-1 đã có trước migration này.
INSERT INTO product_topping_group_links (product_id, group_id)
SELECT product_id, id FROM topping_groups WHERE product_id IS NOT NULL;

DROP INDEX IF EXISTS idx_topping_groups_product;
ALTER TABLE topping_groups DROP COLUMN product_id;

CREATE INDEX idx_topping_groups_merchant ON topping_groups (merchant_id);
CREATE INDEX idx_topping_group_links_group ON product_topping_group_links (group_id);

COMMENT ON TABLE topping_groups IS 'Nhóm tuỳ chọn thêm (topping, size, độ ngọt...) — thuộc về 1 cửa hàng, gắn được vào nhiều sản phẩm qua product_topping_group_links';

COMMIT;
