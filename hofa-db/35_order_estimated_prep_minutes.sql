-- Thời gian làm đơn dự kiến do cửa hàng tự chỉnh lúc trượt nhận đơn (màn nhận đơn store app)
-- — mặc định gợi ý bằng merchants.avg_prep_minutes nhưng cửa hàng có thể tăng/giảm riêng cho
-- từng đơn cụ thể (đơn nhiều món hơn thường cần lâu hơn mức trung bình). NULL = đơn cũ trước
-- migration này, hoặc cửa hàng bỏ qua không chỉnh (tự động nhận khi hết giờ).
ALTER TABLE orders ADD COLUMN estimated_prep_minutes INTEGER;
COMMENT ON COLUMN orders.estimated_prep_minutes IS
  'Thời gian làm đơn dự kiến (phút) cửa hàng xác nhận lúc nhận đơn — gợi ý mặc định lấy từ merchants.avg_prep_minutes';
