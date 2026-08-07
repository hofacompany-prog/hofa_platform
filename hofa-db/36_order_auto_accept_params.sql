-- Đơn bị đánh dấu trễ khi chuyển sang ready_for_pickup trễ hơn confirmed_at + estimated_prep_minutes.
ALTER TABLE orders ADD COLUMN late_minutes INTEGER;
COMMENT ON COLUMN orders.late_minutes IS
  'Số phút cửa hàng làm trễ so với estimated_prep_minutes, tính khi đơn chuyển sang ready_for_pickup. NULL = đúng giờ hoặc chưa tới bước đó.';
