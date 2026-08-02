-- ============================================================================
-- Cho phép chọn icon danh mục từ bộ icon dựng sẵn trong app (thay vì bắt buộc tải
-- ảnh lên) — icon_name lưu key tra trong bảng icon tĩnh ở admin/customer app.
--
-- Chạy file này 1 lần trong Supabase SQL Editor (đã đồng bộ vào 01_schema.sql
-- để những lần cài đặt mới không cần chạy lại file này).
-- ============================================================================

ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS icon_name VARCHAR(50);
COMMENT ON COLUMN categories.icon_name IS 'key trong bộ icon dựng sẵn (vd ''food'', ''electronics''), xem IconPickerField ở admin app';
