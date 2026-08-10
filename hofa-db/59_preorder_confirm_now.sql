-- Đổi cách xử lý đơn đặt trước/giá sỉ (sales_model='scheduled'): không còn "ngủ" chờ tới gần
-- giờ giao nữa — nay gửi thẳng về cửa hàng xác nhận NGAY lúc đặt (như đơn tức thời), màn xác
-- nhận luôn ở chế độ thủ công (coi như tắt tự động nhận đơn) bất kể chi nhánh có bật auto-accept
-- hay không (ép ở phía app cửa hàng, không cần cột mới). Khách chỉ huỷ được khi đơn còn
-- pending_payment/placed; sau khi cửa hàng xác nhận (status='confirmed') khách chỉ còn liên hệ
-- cửa hàng, không tự huỷ được nữa (xem POST/PATCH /orders — server/src/routes/orders.js).
--
-- Cột preorder_notified_at (thêm ở 49_preorder_gating.sql) được TÁI SỬ DỤNG với nghĩa mới: đánh
-- dấu đơn đã được sweep tự động chuyển sang 'preparing' đúng lúc còn default_prep_minutes phút
-- nữa tới scheduled_for (chống chạy trùng), không còn nghĩa "đã được đánh thức khỏi trạng thái
-- ngủ" như trước — xem orderOffer.sweepDuePreorders (server/src/orderOffer.js).
COMMENT ON COLUMN orders.preorder_notified_at IS
  'Đơn đặt trước/giá sỉ (sales_model=scheduled) đã được cửa hàng xác nhận (status=confirmed): cờ chống sweep chạy trùng — set NGAY khi sweep định kỳ tự động chuyển đơn sang preparing đúng lúc còn default_prep_minutes phút nữa tới scheduled_for (xem orderOffer.sweepDuePreorders). NULL = chưa tới lúc/chưa được sweep xử lý. Vô nghĩa với đơn instant (sales_model=instant).';
