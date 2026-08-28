-- ============================================================================
-- MIGRATION 101 — Thêm nhãn phiên bản NGƯỜI ĐỌC ĐƯỢC (vd "2.2.0") cho app_update_settings —
-- min_build_number (hofa-db/100_app_update_settings.sql) vẫn là nguồn SO SÁNH thật (khớp build
-- number trong pubspec.yaml), cột này CHỈ để hiện đúng số phiên bản trong nội dung popup ép cập
-- nhật (thay vì chỉ nói chung chung), giống cách PwaVersionService hiện "Phiên bản $version" cho
-- bản web.
-- ============================================================================

ALTER TABLE app_update_settings ADD COLUMN IF NOT EXISTS min_version_label TEXT;
COMMENT ON COLUMN app_update_settings.min_version_label IS
  'Số phiên bản hiển thị trong popup ép cập nhật (vd "2.2.0", khớp version: X.Y.Z trong
   pubspec.yaml) — chỉ để hiện chữ cho rõ, KHÔNG dùng để so sánh (so bằng min_build_number).';
