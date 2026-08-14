-- ============================================================================
-- MIGRATION 74 — Nhắn tin trong đơn hàng: 2 kênh riêng biệt cho mỗi đơn — Khách hàng ↔ Tài xế
-- và Khách hàng ↔ Cửa hàng. Chỉ mở trong lúc đơn đang vận hành (mọi trạng thái trừ
-- cancelled/refunded) cho tới khi giao xong (delivered_at) + chat_settings.hours_after_delivered
-- giờ (mặc định 1 giờ, admin chỉnh) — hết khoảng này thì app tự ẩn lối vào nhắn tin (client tính
-- từ order.status/delivered_at + chat-settings), server chặn gửi tin mới ở đúng mốc này làm
-- nguồn sự thật (đọc lịch sử cũ vẫn được, chỉ chặn POST mới). Truy cập CHỈ qua chi tiết đơn
-- hàng — không có màn hộp thư nhắn tin riêng.
-- ============================================================================

CREATE TABLE chat_settings (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  hours_after_delivered INTEGER NOT NULL DEFAULT 1 CHECK (hours_after_delivered >= 0),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by            UUID REFERENCES users(id) ON DELETE SET NULL
);
COMMENT ON TABLE chat_settings IS
  'Số giờ được nhắn tin thêm sau khi đơn giao xong — chỉ giữ 1 dòng (mới nhất theo updated_at) đang áp dụng, admin sửa qua GET/PATCH /chat-settings.';

INSERT INTO chat_settings (hours_after_delivered) VALUES (1);

CREATE TABLE order_messages (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  channel     TEXT NOT NULL CHECK (channel IN ('customer_driver', 'customer_merchant')),
  sender_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sender_role user_role NOT NULL,
  body        TEXT,
  image_url   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT order_messages_body_or_image CHECK (body IS NOT NULL OR image_url IS NOT NULL)
);
COMMENT ON TABLE order_messages IS
  'Tin nhắn trong 1 đơn hàng, 2 kênh riêng (channel) — customer_driver và customer_merchant, xem GET/POST /orders/:orderId/messages (server).';
COMMENT ON COLUMN order_messages.channel IS 'customer_driver = khách nhắn với tài xế, customer_merchant = khách nhắn với cửa hàng — 2 luồng độc lập trong cùng 1 đơn.';

CREATE INDEX idx_order_messages_order_channel ON order_messages (order_id, channel, created_at);
