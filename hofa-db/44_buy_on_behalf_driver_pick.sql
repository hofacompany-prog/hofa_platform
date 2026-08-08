-- Cho khách tự chọn tài xế ưng ý cho đơn mua hộ (buy_on_behalf), thay vì hệ thống tự gán tài
-- xế gần nhất (xem hofa-db/43_buy_on_behalf_driver_dispatch.sql). Khách chọn ngay lúc đặt đơn;
-- nếu tài xế đã chọn từ chối/hết hạn thì KHÔNG tự động chuyển tài xế khác như đơn thường —
-- server báo lại cho khách tự chọn người khác (xem server/src/dispatch.js repickNeeded).

ALTER TABLE orders ADD COLUMN selected_driver_id UUID REFERENCES drivers(id) ON DELETE SET NULL;
COMMENT ON COLUMN orders.selected_driver_id IS
  'Tài xế khách tự chọn cho đơn mua hộ (buy_on_behalf) — NULL nghĩa là chưa chọn hoặc cần chọn lại sau khi tài xế trước từ chối/hết hạn';
