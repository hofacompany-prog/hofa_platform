-- Phí mua hộ MẶC ĐỊNH TOÀN SÀN — admin cấu hình 1 lần ở web admin (Tài chính > Phí mua hộ),
-- dùng làm khuôn COPY sang merchants.buy_on_behalf_fee_basis + merchant_fee_tiers cho MỖI cửa
-- hàng merchant_type='buy_on_behalf' MỚI TẠO (xem POST /merchants trong merchants.js, và
-- POST /gas-sync/apply trong gasSync.js). Sau khi copy, sửa/xoá bậc phí toàn sàn ở đây KHÔNG
-- ảnh hưởng ngược lại cửa hàng đã tạo trước đó — admin vẫn chỉnh riêng từng cửa hàng qua
-- merchant_fee_tiers như bình thường (xem hofa-db/28_merchant_buy_on_behalf.sql). Bảng này
-- KHÔNG được create_order() đọc trực tiếp, chỉ dùng đúng 1 lần lúc tạo cửa hàng.

CREATE TABLE platform_buy_on_behalf_fee_settings (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  fee_basis   VARCHAR(10) NOT NULL DEFAULT 'value',
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID REFERENCES users(id) ON DELETE SET NULL,

  CONSTRAINT platform_buy_on_behalf_fee_basis_valid CHECK (fee_basis IN ('quantity', 'value'))
);
COMMENT ON TABLE platform_buy_on_behalf_fee_settings IS
  'Cách tính ngưỡng bậc phí mua hộ mặc định toàn sàn — chỉ giữ 1 dòng đang áp dụng (dòng mới
  nhất theo updated_at, cùng pattern delivery_radius_settings/voucher_settings), admin sửa qua
  GET/PATCH /platform-fee-settings.';

INSERT INTO platform_buy_on_behalf_fee_settings (fee_basis) VALUES ('value');

CREATE TABLE platform_buy_on_behalf_fee_tiers (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  min_threshold     INTEGER NOT NULL,   -- số lượng sản phẩm hoặc VNĐ, tuỳ fee_basis ở trên
  max_threshold     INTEGER,            -- NULL = không giới hạn trên
  fee_type          VARCHAR(10) NOT NULL,
  fee_fixed_amount  INTEGER,            -- VNĐ — bắt buộc khi fee_type = 'fixed'
  fee_percent       NUMERIC(5,2),       -- % giá trị đơn — bắt buộc khi fee_type = 'percent'
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT platform_fee_tiers_threshold_valid CHECK (
    min_threshold >= 0 AND (max_threshold IS NULL OR max_threshold >= min_threshold)
  ),
  CONSTRAINT platform_fee_tiers_type_valid CHECK (fee_type IN ('fixed', 'percent')),
  CONSTRAINT platform_fee_tiers_amount_valid CHECK (
    (fee_type = 'fixed'    AND fee_fixed_amount IS NOT NULL AND fee_fixed_amount >= 0 AND fee_percent IS NULL)
    OR
    (fee_type = 'percent'  AND fee_percent IS NOT NULL AND fee_percent >= 0 AND fee_percent <= 100 AND fee_fixed_amount IS NULL)
  ),
  UNIQUE (min_threshold)
);
COMMENT ON TABLE platform_buy_on_behalf_fee_tiers IS
  'Bậc phí mua hộ mặc định toàn sàn — admin cấu hình ở web admin, copy nguyên xi sang
  merchant_fee_tiers cho MỖI cửa hàng merchant_type=''buy_on_behalf'' mới tạo. Không tự động áp
  ngược lại cửa hàng đã có sẵn.';
CREATE INDEX idx_platform_fee_tiers_threshold ON platform_buy_on_behalf_fee_tiers (min_threshold);
