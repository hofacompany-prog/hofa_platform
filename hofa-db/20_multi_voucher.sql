-- Cho phép áp dụng NHIỀU voucher cùng lúc trên 1 đơn (thay vì đúng 1 voucher như trước) —
-- số lượng tối đa admin cấu hình qua bảng voucher_settings (mục "Voucher" trên web admin).
--
-- orders.voucher_code (VARCHAR đơn) không còn đủ để lưu nhiều mã, và không app nào đang
-- đọc cột này (voucher_redemptions đã là nguồn ghi nhận đầy đủ, đúng 1 dòng/voucher/đơn từ
-- trước tới giờ) nên xoá thẳng thay vì đổi kiểu — tránh phải giữ thêm 1 cột không ai dùng.
BEGIN;

CREATE TABLE IF NOT EXISTS voucher_settings (
  id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  max_vouchers_per_order INTEGER NOT NULL DEFAULT 1,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by             UUID REFERENCES users(id) ON DELETE SET NULL,

  CONSTRAINT voucher_settings_max_valid CHECK (max_vouchers_per_order >= 1)
);
COMMENT ON TABLE voucher_settings IS
  'Số voucher tối đa được áp dụng cùng lúc trên 1 đơn — chỉ giữ 1 dòng (dòng mới nhất theo
  updated_at) đang áp dụng, admin sửa qua GET/PATCH /voucher-settings';

INSERT INTO voucher_settings (max_vouchers_per_order)
SELECT 1
WHERE NOT EXISTS (SELECT 1 FROM voucher_settings);

ALTER TABLE orders DROP COLUMN IF EXISTS voucher_code;

-- p_voucher_code (1 mã, kiểu VARCHAR) đổi thành p_voucher_codes (mảng, VARCHAR[]) bên
-- dưới — CREATE OR REPLACE FUNCTION không thay thế được hàm cũ khi đổi KIỂU tham số
-- (Postgres coi đó là 1 overload MỚI, không phải thay thế), nên phải xoá hết mọi bản cũ
-- của create_order trước, tránh còn 2 hàm trùng tên gây lỗi "not unique" khi gọi/COMMENT.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT oid::regprocedure AS sig FROM pg_proc WHERE proname = 'create_order' LOOP
    EXECUTE format('DROP FUNCTION %s', r.sig);
  END LOOP;
END $$;

-- Chốt giá + tạo đơn — bản này thay p_voucher_code (1 mã) bằng p_voucher_codes (mảng mã),
-- xét từng mã lần lượt (đủ điều kiện tối thiểu, còn lượt, chưa dùng trùng), cộng dồn tổng
-- giảm giá, chặn vượt quá voucher_settings.max_vouchers_per_order, rồi ghi 1 dòng
-- voucher_redemptions cho MỖI voucher đã áp dụng (bảng này vốn đã cho phép nhiều voucher
-- khác nhau trên cùng 1 đơn — chỉ cấm trùng đúng 1 voucher 2 lần).
CREATE OR REPLACE FUNCTION create_order(
  p_customer_id      UUID,
  p_merchant_id      UUID,
  p_branch_id        UUID,
  p_sales_model      sales_model,
  p_items            JSONB,
  p_ship_recipient_name  VARCHAR,
  p_ship_recipient_phone VARCHAR,
  p_ship_line1       VARCHAR,
  p_ship_province    VARCHAR,
  p_ship_ward        VARCHAR DEFAULT NULL,
  p_ship_district    VARCHAR DEFAULT NULL,
  p_ship_latitude    NUMERIC DEFAULT NULL,
  p_ship_longitude   NUMERIC DEFAULT NULL,
  p_ship_note        TEXT DEFAULT NULL,
  p_payment_method   payment_method DEFAULT 'cod',
  p_delivery_fee     INTEGER DEFAULT 0,
  p_tax_amount       INTEGER DEFAULT 0,
  p_voucher_codes    VARCHAR[] DEFAULT NULL,
  p_scheduled_for    TIMESTAMPTZ DEFAULT NULL,
  p_customer_note    TEXT DEFAULT NULL
) RETURNS orders AS $$
DECLARE
  v_item          JSONB;
  v_variant       product_variants;
  v_subtotal      INTEGER := 0;
  v_unit_price    INTEGER;
  v_line_total    INTEGER;
  v_discount      INTEGER := 0;
  v_voucher_discount INTEGER;
  v_voucher       vouchers;
  v_voucher_code  VARCHAR;
  v_max_vouchers  INTEGER;
  v_redemptions_json JSONB := '[]'::jsonb;
  v_order         orders;
  v_user_redemptions INTEGER;
  v_items_json    JSONB := '[]'::jsonb;   -- gom item đã chốt giá, chỉ ghi vào order_items SAU KHI có order.id
  v_commission_rate NUMERIC;
  v_topping_sum   INTEGER;
  v_toppings_json JSONB;
  v_topping_row   RECORD;
  v_elem          JSONB;
  v_order_item_id UUID;
  v_order_quantity_total INTEGER;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND merchant_id = p_merchant_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Chi nhánh không thuộc cửa hàng này' USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Đơn hàng phải có ít nhất 1 món' USING ERRCODE = 'check_violation';
  END IF;

  SELECT commission_rate INTO v_commission_rate FROM merchants WHERE id = p_merchant_id;

  -- Tổng số phần của CẢ đơn (gộp mọi sản phẩm) — dùng để so bậc "đặt trước"
  -- (lead_time_days > 0), vì bậc đó tính theo tổng số phần đặt trong cùng 1 lần giao,
  -- không phân biệt đặt món gì.
  SELECT COALESCE(SUM((elem->>'quantity')::INTEGER), 0) INTO v_order_quantity_total
    FROM jsonb_array_elements(p_items) elem;

  -- Bước 1: chốt giá + giữ tồn kho cho từng món. CHƯA insert orders/order_items ở đây,
  -- vì orders có CHECK (total_amount = subtotal + delivery_fee + tax_amount - discount_amount) —
  -- phải biết subtotal cuối cùng (và cả voucher) trước khi insert được 1 lần cho khớp ràng buộc.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_variant FROM product_variants
     WHERE id = (v_item->>'variant_id')::UUID AND is_active
     FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Biến thể sản phẩm % không tồn tại hoặc đã ngừng bán', v_item->>'variant_id'
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF (v_item->>'quantity')::INTEGER <= 0 THEN
      RAISE EXCEPTION 'Số lượng phải lớn hơn 0' USING ERRCODE = 'check_violation';
    END IF;

    PERFORM reserve_inventory(p_branch_id, v_variant.id, (v_item->>'quantity')::INTEGER);

    -- Topping khách chọn (nếu có) — giá cộng thêm/đơn vị, không tin giá client gửi,
    -- chỉ nhận topping_id rồi tự tra giá thật từ product_toppings.
    v_topping_sum := 0;
    v_toppings_json := '[]'::jsonb;
    FOR v_topping_row IN
      SELECT pt.id, pt.name, pt.price FROM product_toppings pt
       WHERE pt.id IN (
         SELECT (jsonb_array_elements_text(COALESCE(v_item->'topping_ids', '[]'::jsonb)))::UUID
       )
    LOOP
      v_topping_sum := v_topping_sum + v_topping_row.price;
      v_toppings_json := v_toppings_json || jsonb_build_object(
        'topping_id', v_topping_row.id, 'name', v_topping_row.name, 'price', v_topping_row.price
      );
    END LOOP;

    v_unit_price := resolve_variant_price(
      v_variant.id, (v_item->>'quantity')::INTEGER, v_order_quantity_total,
      COALESCE((v_item->>'days_count')::INTEGER, 0),
      COALESCE(v_item->>'order_kind', '') = 'preorder',
      v_variant.price
    ) + v_topping_sum;
    v_line_total := v_unit_price * (v_item->>'quantity')::INTEGER;
    v_subtotal   := v_subtotal + v_line_total;

    SELECT v_items_json || jsonb_build_object(
      'variant_id', v_variant.id,
      'product_name', p.name,
      'variant_name', v_variant.name,
      'sku', v_variant.sku,
      'unit', p.unit,
      'unit_price', v_unit_price,
      'quantity', (v_item->>'quantity')::INTEGER,
      'line_total', v_line_total,
      'note', v_item->>'note',
      'toppings', v_toppings_json
    ) INTO v_items_json
    FROM products p WHERE p.id = v_variant.product_id;
  END LOOP;

  -- Áp mã giảm giá (nếu có) — nhiều mã cùng lúc, tối đa voucher_settings.max_vouchers_per_order.
  IF p_voucher_codes IS NOT NULL AND array_length(p_voucher_codes, 1) > 0 THEN
    IF array_length(p_voucher_codes, 1) <> (SELECT COUNT(DISTINCT x) FROM unnest(p_voucher_codes) x) THEN
      RAISE EXCEPTION 'Không được dùng trùng lặp cùng 1 mã giảm giá' USING ERRCODE = 'check_violation';
    END IF;

    SELECT max_vouchers_per_order INTO v_max_vouchers FROM voucher_settings ORDER BY updated_at DESC LIMIT 1;
    IF array_length(p_voucher_codes, 1) > COALESCE(v_max_vouchers, 1) THEN
      RAISE EXCEPTION 'Chỉ được dùng tối đa % mã giảm giá cho 1 đơn', COALESCE(v_max_vouchers, 1)
        USING ERRCODE = 'check_violation';
    END IF;

    FOREACH v_voucher_code IN ARRAY p_voucher_codes LOOP
      SELECT * INTO v_voucher FROM vouchers
       WHERE code = v_voucher_code AND is_active
         AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now())
         AND (merchant_id IS NULL OR merchant_id = p_merchant_id)
       FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Mã giảm giá % không hợp lệ hoặc đã hết hạn', v_voucher_code USING ERRCODE = 'check_violation';
      END IF;

      IF v_subtotal < v_voucher.min_order_amount THEN
        RAISE EXCEPTION 'Đơn chưa đạt giá trị tối thiểu % để dùng mã %', v_voucher.min_order_amount, v_voucher_code
          USING ERRCODE = 'check_violation';
      END IF;

      IF v_voucher.usage_limit IS NOT NULL AND v_voucher.used_count >= v_voucher.usage_limit THEN
        RAISE EXCEPTION 'Mã % đã hết lượt dùng', v_voucher_code USING ERRCODE = 'check_violation';
      END IF;

      SELECT COUNT(*) INTO v_user_redemptions FROM voucher_redemptions
       WHERE voucher_id = v_voucher.id AND user_id = p_customer_id;
      IF v_user_redemptions >= v_voucher.usage_limit_per_user THEN
        RAISE EXCEPTION 'Bạn đã dùng hết lượt cho mã %', v_voucher_code USING ERRCODE = 'check_violation';
      END IF;

      IF v_voucher.discount_type = 'percent' THEN
        v_voucher_discount := ROUND(v_subtotal * v_voucher.discount_value / 100.0);
        IF v_voucher.max_discount IS NOT NULL THEN
          v_voucher_discount := LEAST(v_voucher_discount, v_voucher.max_discount);
        END IF;
      ELSIF v_voucher.discount_type = 'fixed' THEN
        v_voucher_discount := v_voucher.discount_value;
      ELSIF v_voucher.discount_type = 'free_shipping' THEN
        v_voucher_discount := p_delivery_fee;
      END IF;

      v_discount := v_discount + v_voucher_discount;
      v_redemptions_json := v_redemptions_json || jsonb_build_object(
        'voucher_id', v_voucher.id, 'discount_amount', v_voucher_discount
      );

      UPDATE vouchers SET used_count = used_count + 1 WHERE id = v_voucher.id;
    END LOOP;

    v_discount := LEAST(v_discount, v_subtotal + p_delivery_fee); -- không cho âm tiền
  END IF;

  -- Bước 2: giờ mới insert orders — MỘT LẦN DUY NHẤT, với số liệu đã chốt xong,
  -- để khớp ngay từ đầu với CHECK orders_total_matches.
  INSERT INTO orders (
    customer_id, merchant_id, branch_id, sales_model, status,
    ship_recipient_name, ship_recipient_phone, ship_line1, ship_ward, ship_district,
    ship_province, ship_latitude, ship_longitude, ship_note,
    subtotal, delivery_fee, discount_amount, tax_amount, total_amount,
    commission_amount, merchant_payout,
    payment_method, payment_status, scheduled_for, customer_note
  ) VALUES (
    p_customer_id, p_merchant_id, p_branch_id, p_sales_model,
    (CASE WHEN p_payment_method = 'cod' THEN 'placed' ELSE 'pending_payment' END)::order_status,
    p_ship_recipient_name, p_ship_recipient_phone, p_ship_line1, p_ship_ward, p_ship_district,
    p_ship_province, p_ship_latitude, p_ship_longitude, p_ship_note,
    v_subtotal, p_delivery_fee, v_discount, p_tax_amount, v_subtotal + p_delivery_fee + p_tax_amount - v_discount,
    ROUND(v_subtotal * v_commission_rate / 100.0), v_subtotal - ROUND(v_subtotal * v_commission_rate / 100.0),
    p_payment_method, 'pending', p_scheduled_for, p_customer_note
  ) RETURNING * INTO v_order;

  -- Bước 3: giờ mới ghi order_items, dùng order.id vừa có — insert từng dòng (không
  -- bulk) để lấy được id vừa tạo, dùng ghi order_item_toppings tương ứng ngay sau đó.
  FOR v_elem IN SELECT * FROM jsonb_array_elements(v_items_json) LOOP
    INSERT INTO order_items (order_id, variant_id, product_name, variant_name, sku, unit, unit_price, quantity, line_total, note)
    VALUES (
      v_order.id, (v_elem->>'variant_id')::UUID, v_elem->>'product_name', v_elem->>'variant_name', v_elem->>'sku',
      v_elem->>'unit', (v_elem->>'unit_price')::INTEGER, (v_elem->>'quantity')::INTEGER, (v_elem->>'line_total')::INTEGER, v_elem->>'note'
    ) RETURNING id INTO v_order_item_id;

    IF jsonb_array_length(COALESCE(v_elem->'toppings', '[]'::jsonb)) > 0 THEN
      INSERT INTO order_item_toppings (order_item_id, topping_id, name, price)
      SELECT v_order_item_id, (t->>'topping_id')::UUID, t->>'name', (t->>'price')::INTEGER
      FROM jsonb_array_elements(v_elem->'toppings') t;
    END IF;
  END LOOP;

  IF jsonb_array_length(v_redemptions_json) > 0 THEN
    INSERT INTO voucher_redemptions (voucher_id, user_id, order_id, discount_amount)
    SELECT (r->>'voucher_id')::UUID, p_customer_id, v_order.id, (r->>'discount_amount')::INTEGER
    FROM jsonb_array_elements(v_redemptions_json) r;
  END IF;

  RETURN v_order;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION create_order IS
  'Tạo đơn: chốt giá qua resolve_variant_price (bậc giá sỉ theo số lượng riêng món; bậc đặt trước theo tổng số lượng cả đơn + số ngày/tuần riêng món, chỉ xét đúng loại bậc theo order_kind của từng món; không khớp thì giá gốc), giữ chỗ tồn kho, áp NHIỀU voucher cùng lúc (tối đa voucher_settings.max_vouchers_per_order) — tất cả trong 1 transaction';

COMMIT;
