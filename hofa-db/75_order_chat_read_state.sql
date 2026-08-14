-- ============================================================================
-- MIGRATION 75 — Trạng thái đã đọc cho nhắn tin trong đơn (hofa-db/74_order_chat.sql) — để hiện
-- số tin nhắn CHƯA ĐỌC (badge nhỏ) ở nút nhắn tin trong chi tiết đơn, không cần mở màn chat mới
-- biết có tin mới. Mỗi (đơn, kênh, người dùng) chỉ giữ đúng 1 mốc "đã đọc tới lúc nào" — GET
-- /orders/:orderId/messages tự cập nhật mốc này = now() mỗi lần gọi (coi như mở màn chat là đã
-- đọc hết), không cần API đánh dấu đọc riêng.
-- ============================================================================

CREATE TABLE order_message_reads (
  order_id     UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  channel      TEXT NOT NULL CHECK (channel IN ('customer_driver', 'customer_merchant')),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (order_id, channel, user_id)
);
COMMENT ON TABLE order_message_reads IS
  'Mốc "đã đọc tới lúc nào" của 1 người dùng trong 1 kênh nhắn tin của 1 đơn — dùng tính số tin chưa đọc ở GET /orders/:orderId/messages/unread-counts.';
