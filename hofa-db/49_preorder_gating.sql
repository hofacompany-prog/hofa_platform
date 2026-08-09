-- Đơn đặt trước (sales_model='scheduled', gồm cả tab "Đặt trước" lẫn "Giá sỉ" ở app khách —
-- cả 2 đều đi qua chung field này) không còn "nổ" ngay lúc tạo như đơn tức thời nữa: cửa hàng
-- chỉ xem được món, chưa nhận thông báo/thao tác được cho tới khi còn đúng default_prep_minutes
-- phút nữa tới scheduled_for — xem orderOffer.sweepDuePreorders (server) + orderOffer.js.
ALTER TABLE orders ADD COLUMN preorder_notified_at TIMESTAMPTZ;
COMMENT ON COLUMN orders.preorder_notified_at IS
  'Đơn đặt trước (sales_model=scheduled): thời điểm được kích hoạt — báo cho cửa hàng + cho phép thao tác, đúng lúc còn default_prep_minutes phút nữa tới scheduled_for (do sweep định kỳ set, xem orderOffer.sweepDuePreorders). NULL = đơn đang "ngủ": cửa hàng chỉ xem được món, chưa thao tác/nhận thông báo được. Đơn scheduled đặt gấp (thời điểm kích hoạt đã qua ngay lúc tạo) được set NGAY ở POST /orders, coi như đơn tức thời. Vô nghĩa với đơn instant (sales_model=instant).';
