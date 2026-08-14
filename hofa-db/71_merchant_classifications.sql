-- ============================================================================
-- MIGRATION 71 — Phân loại cửa hàng (vd "Nhà hàng", "Cà phê", "Siêu thị mini") — TÁCH HẲN khỏi
-- `categories` (danh mục ngành hàng sản phẩm, dùng cho lưới danh mục trang chủ/lọc sản phẩm).
-- 1 cửa hàng chọn được NHIỀU phân loại cùng lúc (bảng nối nhiều-nhiều) — admin quản lý danh
-- sách phân loại (mirror bảng `banks`, hofa-db/46_driver_bank_and_verification.sql), cửa hàng/
-- admin tự gắn phân loại cho từng cửa hàng lúc tạo/sửa.
-- ============================================================================

CREATE TABLE merchant_classifications (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE merchant_classifications IS
  'Danh sách phân loại cửa hàng (Nhà hàng/Cà phê/Siêu thị mini...) admin quản lý — xem GET/POST/PATCH/DELETE /merchant-classifications. Khác hẳn categories (danh mục ngành hàng sản phẩm).';

CREATE TABLE merchant_classification_links (
  merchant_id      UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  classification_id UUID NOT NULL REFERENCES merchant_classifications(id) ON DELETE CASCADE,
  PRIMARY KEY (merchant_id, classification_id)
);
COMMENT ON TABLE merchant_classification_links IS
  'Nhiều-nhiều cửa hàng ↔ phân loại — ghi đè toàn bộ qua PUT /merchants/:id/classifications (xoá hết rồi insert lại đúng danh sách mới, cùng pattern PUT /branches/:id/hours).';

CREATE INDEX idx_merchant_classification_links_classification ON merchant_classification_links (classification_id);
