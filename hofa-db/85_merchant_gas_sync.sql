-- ============================================================================
-- MIGRATION 85 — merchants.is_gas_synced: đánh dấu cửa hàng được tạo/quản lý qua công cụ nhập
-- liệu Google Apps Script (gas/store_folder_sync.gs, tab "Đồng bộ CSDL"). Nhóm endpoint
-- /gas-sync/* (server/src/routes/gasSync.js) CHỈ được phép sửa cửa hàng có cờ này = true (tạo
-- mới qua đường đó luôn tự set true) — chặn cứng ở tầng server dựa vào ID thật, không dựa vào
-- so khớp tên, để lỡ tay gõ trùng tên trong sheet cũng không bao giờ đụng phải cửa hàng thật đã
-- có sẵn trong hệ thống (tạo qua app/admin bình thường).
-- ============================================================================

ALTER TABLE merchants ADD COLUMN is_gas_synced BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN merchants.is_gas_synced IS
  'true = cửa hàng được tạo/đồng bộ qua GAS (gas/store_folder_sync.gs, tab Đồng bộ CSDL) — chỉ cửa hàng có cờ này mới bị nhóm endpoint /gas-sync/* sửa, mọi cửa hàng khác (tạo qua app/admin bình thường) không bao giờ bị đụng tới dù trùng tên.';
