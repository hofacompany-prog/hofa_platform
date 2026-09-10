-- ============================================================================
-- MIGRATION 110 — Công tắc toàn sàn: ẩn/hiện sản phẩm "Đặt trước/Bán sỉ" (sales_model=
-- 'scheduled') ở app Khách hàng. Admin bật/tắt bất cứ lúc nào qua PATCH
-- /wholesale-preorder-settings — KHÔNG xoá/đổi dữ liệu sản phẩm, chỉ ẩn khỏi mọi kết quả
-- duyệt/tìm kiếm của khách (GET /products) khi tắt. Cửa hàng/admin vẫn quản lý được sản phẩm
-- loại này bình thường (server/src/routes/products.js chỉ lọc nhánh khách xem, không lọc
-- nhánh chủ cửa hàng/admin xem sản phẩm của chính họ).
-- ============================================================================

CREATE TABLE wholesale_preorder_settings (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  enabled     BOOLEAN NOT NULL DEFAULT true,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID REFERENCES users(id) ON DELETE SET NULL
);
COMMENT ON TABLE wholesale_preorder_settings IS
  'Công tắc toàn sàn — enabled=false thì GET /products (khách duyệt/tìm kiếm) tự lọc bỏ hết sản
   phẩm sales_model=''scheduled'' (Đặt trước/Bán sỉ), không đụng tới dữ liệu sản phẩm/đơn hàng cũ.
   Chỉ giữ 1 dòng đang áp dụng (dòng mới nhất theo updated_at), cùng pattern small_order_fee_
   settings. Admin cấu hình qua PATCH /wholesale-preorder-settings.';

-- Yêu cầu ban đầu: ẩn NGAY — admin bật lại bất cứ lúc nào qua web admin.
INSERT INTO wholesale_preorder_settings (enabled) VALUES (false);
