-- ============================================================================
-- MIGRATION 89 — Khách/tài xế báo giá sai của 1 biến thể sản phẩm (giá hiện hiển thị vs giá
-- thực tế ngoài đời), admin xem và duyệt. Duyệt thì áp giá thẳng vào product_variants.price
-- qua PATCH /variants/:id (đã có sẵn, admin có quyền qua requireMerchantAccess) — bảng này chỉ
-- lưu chính báo cáo, không tự đổi giá.
-- ============================================================================

CREATE TABLE product_price_reports (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  variant_id      UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  merchant_id     UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  reported_by     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reporter_role   user_role NOT NULL,
  -- Giá đang hiển thị lúc báo cáo (chụp lại) — để admin đối chiếu dù giá thật đã đổi giữa
  -- lúc báo cáo và lúc admin xem xét.
  price_at_report INTEGER NOT NULL CHECK (price_at_report >= 0),
  reported_price  INTEGER NOT NULL CHECK (reported_price >= 0),
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  -- Giá admin THỰC SỰ áp dụng lúc duyệt — có thể khác reported_price nếu admin tự sửa lại.
  final_price     INTEGER,
  reviewed_by     UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE product_price_reports IS
  'Báo cáo giá sai từ khách/tài xế cho 1 biến thể sản phẩm — admin duyệt qua GET/PATCH
   /admin/price-reports, duyệt thì áp final_price vào product_variants.price.';

CREATE INDEX idx_price_reports_status   ON product_price_reports (status, created_at);
CREATE INDEX idx_price_reports_variant  ON product_price_reports (variant_id);
CREATE INDEX idx_price_reports_merchant ON product_price_reports (merchant_id);
