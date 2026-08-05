-- Đổi mã đơn hàng từ dạng dài "HF" + ngày + số thứ tự (vd HF26073000001, 13 ký tự) sang dạng
-- ngắn "<prefix>-" + 3 chữ số ngẫu nhiên (vd HF-482) để đọc qua điện thoại nhanh hơn. Chữ đầu
-- (prefix) chỉnh được ở web admin qua bảng order_settings, không hard-code "HF" trong code nữa.
--
-- Đánh đổi: 3 chữ số chỉ có 1000 tổ hợp nên KHÔNG còn đảm bảo duy nhất tuyệt đối — chấp nhận vì
-- order_code chỉ dùng để đọc/tra cứu, còn hệ thống vẫn xử lý đơn bằng orders.id (UUID) thật.
BEGIN;

CREATE TABLE IF NOT EXISTS order_settings (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code_prefix VARCHAR(10) NOT NULL DEFAULT 'HF',
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT order_settings_prefix_format CHECK (code_prefix ~ '^[A-Za-z0-9]{1,10}$')
);
COMMENT ON TABLE order_settings IS 'Cấu hình toàn sàn cho mã đơn hàng hiển thị (order_code) — hiện chỉ có chữ đầu (prefix)';

INSERT INTO order_settings (code_prefix)
SELECT 'HF' WHERE NOT EXISTS (SELECT 1 FROM order_settings);

ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_order_code_key;

DROP SEQUENCE IF EXISTS order_code_seq;

CREATE OR REPLACE FUNCTION generate_order_code() RETURNS TRIGGER AS $$
DECLARE
  v_prefix VARCHAR(10);
BEGIN
  IF NEW.order_code IS NULL OR NEW.order_code = '' THEN
    SELECT code_prefix INTO v_prefix FROM order_settings ORDER BY updated_at DESC LIMIT 1;
    NEW.order_code := COALESCE(v_prefix, 'HF') || '-' || lpad(floor(random() * 1000)::TEXT, 3, '0');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMIT;
