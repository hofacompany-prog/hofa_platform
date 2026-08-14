-- ============================================================================
-- MIGRATION 83 — SĐT liên hệ admin/hỗ trợ, hiện ở nút "Liên hệ hỗ trợ" trên màn chi tiết
-- cửa hàng MUA HỘ (app khách) — cửa hàng mua hộ không trực tiếp xử lý đơn (tài xế tự đi mua),
-- nên khách cần liên hệ admin thay vì cửa hàng khi có vấn đề.
-- ============================================================================

CREATE TABLE admin_contact_settings (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone      VARCHAR(20),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES users(id)
);
COMMENT ON TABLE admin_contact_settings IS
  'SĐT liên hệ admin/hỗ trợ toàn sàn — app khách gọi/nhắn tin thẳng số này khi cần liên hệ admin
   (hiện tại chỉ dùng ở màn chi tiết cửa hàng mua hộ, xem hofa_customer_app merchant_detail_screen.dart)';
