-- ============================================================================
-- MIGRATION 100 — Ép cập nhật app native (Khách hàng/Tài xế/Cửa hàng) khi có bản mới bắt buộc.
-- Không áp dụng app Admin (web-only, không phát hành qua App Store/Play Store, đã có cơ chế
-- riêng PwaVersionService). Client (main.dart mỗi app) so build number CÀI THẬT trên máy
-- (package_info_plus) với min_build_number ở đây — thấp hơn thì hiện popup KHÔNG có nút bỏ qua,
-- chỉ mở được store đúng nền tảng để cập nhật (xem core/app_update_service.dart mỗi app).
-- ============================================================================

CREATE TABLE app_update_settings (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  app_scope           TEXT NOT NULL UNIQUE CHECK (app_scope IN ('customer', 'driver', 'merchant')),
  min_build_number    INTEGER NOT NULL DEFAULT 1 CHECK (min_build_number > 0),
  ios_store_url       TEXT,
  android_store_url   TEXT,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by          UUID REFERENCES users(id)
);
COMMENT ON TABLE app_update_settings IS
  'Cấu hình ép cập nhật app native theo từng app_scope (customer/driver/merchant) — client so
   build number cài thật với min_build_number, thấp hơn thì bắt buộc cập nhật (không có nút bỏ
   qua), bấm "Cập nhật ngay" mở ios_store_url hoặc android_store_url tuỳ nền tảng đang chạy.
   Admin cấu hình qua PATCH /admin/app-update-settings/:appScope (hofa_admin_app).';

INSERT INTO app_update_settings (app_scope, min_build_number) VALUES
  ('customer', 1), ('driver', 1), ('merchant', 1)
ON CONFLICT (app_scope) DO NOTHING;
