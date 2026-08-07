-- Hộp thư thông báo trong app — trước đây push (FCM) chỉ là tin nhắn tức thời, không lưu
-- lại gì cả nên user tắt app/không cấp quyền push là mất luôn thông báo, không xem lại
-- được. Bảng này lưu MỌI thông báo từng gửi cho 1 user (cả thông báo hệ thống về đơn hàng
-- lẫn thông báo admin gửi tay), độc lập với việc push có tới máy hay không.
--
-- `data` lưu CHÍNH payload đã gửi qua FCM (type, order_id, screen...) — màn danh sách thông
-- báo phía app khi bấm vào 1 dòng chỉ cần gọi lại đúng PushService.handleData(data) hiện có,
-- không cần viết lại logic điều hướng lần 2.
BEGIN;

CREATE TABLE notifications (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       VARCHAR(150) NOT NULL,
  body        VARCHAR(500) NOT NULL,
  data        JSONB NOT NULL DEFAULT '{}'::jsonb,
  read_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE notifications IS
  'Hộp thư thông báo trong app của từng user — 1 dòng cho mỗi lần gửi push (hệ thống hoặc
  admin gửi tay), lưu lại kể cả khi thiết bị không có push_token/không cấp quyền thông báo';
COMMENT ON COLUMN notifications.data IS
  'Payload giống hệt data gửi qua FCM (type, order_id, screen...) — dùng để điều hướng khi
  bấm vào dòng thông báo trong app, xem PushService.handleData() phía Flutter';

CREATE INDEX idx_notifications_user_created ON notifications (user_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications (user_id) WHERE read_at IS NULL;

COMMIT;
