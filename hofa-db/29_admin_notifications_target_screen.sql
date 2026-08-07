-- Cho phép admin chọn app sẽ mở màn nào khi người dùng bấm vào 1 thông báo thủ công — trước
-- đây thông báo kiểu 'admin_broadcast' không có đích đến, bấm vào chỉ mở app ở màn mặc định.
-- Giá trị là 1 đường dẫn route nội bộ của app nhận (vd '/orders', '/products'), khác nhau
-- tuỳ audience_type — xem danh sách hợp lệ ở admin_notifications_target_screens.dart (admin)
-- và cách từng app xử lý ở core/push_service.dart (customer/store/driver).
BEGIN;

ALTER TABLE admin_notifications ADD COLUMN target_screen VARCHAR(50);
COMMENT ON COLUMN admin_notifications.target_screen IS
  'Route nội bộ app nhận sẽ mở khi bấm vào thông báo (vd /orders) — NULL nghĩa là không chỉ định, mở màn mặc định';

COMMIT;
