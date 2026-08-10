-- Cửa hàng yêu thích của khách hàng — icon trái tim ở trang chủ app khách mở màn danh sách
-- này, tim ở thẻ cửa hàng/màn chi tiết cửa hàng để thêm-bớt.
BEGIN;

CREATE TABLE merchant_favorites (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (customer_id, merchant_id)
);
COMMENT ON TABLE merchant_favorites IS
  'Cửa hàng khách đã bấm tim yêu thích — 1 dòng/lần bấm, xoá dòng khi bỏ tim (không xoá mềm, không có ý nghĩa lưu lịch sử ở đây)';

CREATE INDEX idx_merchant_favorites_customer ON merchant_favorites (customer_id, created_at DESC);

COMMIT;
