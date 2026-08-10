-- Bán kính giao hàng: mỗi chi nhánh tự đặt riêng (branches.delivery_radius_km, đã có sẵn từ
-- 01_schema.sql nhưng chưa có ràng buộc/chưa được dùng ở đâu) + 1 mức "mặc định toàn sàn" admin
-- cấu hình chung (bảng mới delivery_radius_settings, cùng pattern shipping_fee_settings/
-- auto_accept_settings — chỉ giữ 1 dòng mới nhất theo updated_at).
--
-- Cách dùng 2 mức này khi hiện danh sách cửa hàng/sản phẩm cho khách (GET /merchants, GET
-- /merchants/:id, GET /products — xem server/src/routes/merchants.js, products.js):
--   - Khoảng cách khách → chi nhánh gần nhất > GREATEST(delivery_radius_km chi nhánh đó,
--     default_radius_km) → ẨN hẳn cửa hàng/sản phẩm đó khỏi danh sách.
--   - Nằm trong khoảng [delivery_radius_km chi nhánh, default_radius_km] (vượt bán kính riêng
--     nhưng vẫn trong mức mặc định toàn sàn) → vẫn hiện, khoảng cách hiện màu cam cảnh báo.
--   - Trong bán kính riêng của chi nhánh → hiện bình thường.
-- default_radius_km vì vậy đóng vai trò "trần" nới rộng thêm cho các chi nhánh đặt bán kính
-- riêng nhỏ hơn mức này, không phải giá trị thay thế.

ALTER TABLE branches ADD CONSTRAINT branches_delivery_radius_valid
  CHECK (delivery_radius_km > 0 AND delivery_radius_km <= 100);
COMMENT ON COLUMN branches.delivery_radius_km IS
  'Bán kính giao hàng riêng của chi nhánh (km) — chủ cửa hàng tự đặt lúc thêm/sửa chi nhánh. So với delivery_radius_settings.default_radius_km (mức mặc định toàn sàn) để quyết định ẩn/hiện + tô màu cảnh báo khoảng cách cho khách, xem GET /merchants, /merchants/:id, /products.';

CREATE TABLE IF NOT EXISTS delivery_radius_settings (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  default_radius_km NUMERIC(5,2) NOT NULL DEFAULT 5,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by        UUID REFERENCES users(id) ON DELETE SET NULL,

  CONSTRAINT delivery_radius_default_valid CHECK (default_radius_km > 0 AND default_radius_km <= 100)
);
COMMENT ON TABLE delivery_radius_settings IS
  'Bán kính giao hàng mặc định toàn sàn — chỉ giữ 1 dòng đang áp dụng (dòng mới nhất theo updated_at), admin sửa qua GET/PATCH /delivery-radius-settings. Đóng vai trò trần nới rộng cho chi nhánh có bán kính riêng nhỏ hơn mức này (xem comment cột branches.delivery_radius_km).';

INSERT INTO delivery_radius_settings (default_radius_km)
SELECT 5 WHERE NOT EXISTS (SELECT 1 FROM delivery_radius_settings);
