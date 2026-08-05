-- Thêm loại mã đơn thứ 2: đơn giao ngay (sales_model = 'instant') tiếp tục dùng
-- code_prefix_instant (mặc định 'HF'), còn đơn đặt trước/giá sỉ (sales_model = 'scheduled')
-- dùng code_prefix_scheduled riêng (mặc định 'DT') — cả 2 chỉnh được ở web admin, mục Mã đơn hàng.
BEGIN;

ALTER TABLE order_settings RENAME COLUMN code_prefix TO code_prefix_instant;

ALTER TABLE order_settings
  ADD COLUMN code_prefix_scheduled VARCHAR(10) NOT NULL DEFAULT 'DT';

ALTER TABLE order_settings
  DROP CONSTRAINT IF EXISTS order_settings_prefix_format,
  ADD CONSTRAINT order_settings_prefix_instant_format   CHECK (code_prefix_instant   ~ '^[A-Za-z0-9]{1,10}$'),
  ADD CONSTRAINT order_settings_prefix_scheduled_format  CHECK (code_prefix_scheduled ~ '^[A-Za-z0-9]{1,10}$');

CREATE OR REPLACE FUNCTION generate_order_code() RETURNS TRIGGER AS $$
DECLARE
  v_prefix_instant   VARCHAR(10);
  v_prefix_scheduled VARCHAR(10);
BEGIN
  IF NEW.order_code IS NULL OR NEW.order_code = '' THEN
    SELECT code_prefix_instant, code_prefix_scheduled
      INTO v_prefix_instant, v_prefix_scheduled
      FROM order_settings ORDER BY updated_at DESC LIMIT 1;
    NEW.order_code :=
      COALESCE(
        CASE WHEN NEW.sales_model = 'scheduled' THEN v_prefix_scheduled ELSE v_prefix_instant END,
        CASE WHEN NEW.sales_model = 'scheduled' THEN 'DT' ELSE 'HF' END
      ) || '-' || lpad(floor(random() * 1000)::TEXT, 3, '0');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMIT;
