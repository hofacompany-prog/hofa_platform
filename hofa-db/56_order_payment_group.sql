-- "Thanh toán theo tuần" cho đơn đặt trước tạo nhiều lần giao (mỗi lần giao = 1 đơn riêng,
-- xem create_order) — khách chuyển khoản 1 lần cho ĐƠN ĐẦU TIÊN trong tuần, các đơn sau
-- trong cùng tuần đó KHÔNG bắt trả riêng nữa. Chỉ là 1 nhãn tham chiếu để cửa hàng biết đơn
-- này đã gộp thanh toán với đơn nào — KHÔNG tự đổi payment_status, cửa hàng vẫn tự xác nhận
-- đã nhận tiền y hệt quy trình chuyển khoản hiện có (không tự động tin khách đã trả tiền).
ALTER TABLE orders ADD COLUMN payment_group_order_id UUID REFERENCES orders(id) ON DELETE SET NULL;
COMMENT ON COLUMN orders.payment_group_order_id IS 'Đơn đầu tiên trong tuần mà đơn này gộp thanh toán chung với — NULL nghĩa là đơn tự thanh toán riêng';

CREATE INDEX idx_orders_payment_group ON orders (payment_group_order_id) WHERE payment_group_order_id IS NOT NULL;
