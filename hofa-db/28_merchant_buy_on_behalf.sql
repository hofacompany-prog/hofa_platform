-- Thêm phân loại cửa hàng "Mua hộ" (buy_on_behalf) — cửa hàng dạng này được cộng thêm 1
-- khoản phí mua hộ vào tổng thanh toán, tính theo bậc do admin cấu hình lúc tạo/sửa cửa
-- hàng (không phải chủ cửa hàng tự cấu hình như wholesale_tiers). Mỗi cửa hàng chọn MỘT
-- cách tính ngưỡng bậc (buy_on_behalf_fee_basis): theo số lượng sản phẩm cả đơn, hoặc theo
-- giá trị đơn hàng (subtotal) — rồi từng bậc tự chọn phí cố định (VNĐ) hoặc phí theo %.
-- ALTER TYPE ... ADD VALUE phải tự đứng 1 transaction riêng — Postgres không cho dùng giá
-- trị enum vừa thêm ngay trong CÙNG transaction đã thêm nó (kể cả các câu lệnh phía sau
-- trong cùng file này, nếu gộp chung 1 BEGIN/COMMIT sẽ lỗi "unsafe use of new value").
BEGIN;
ALTER TYPE merchant_type ADD VALUE 'buy_on_behalf';
COMMIT;

BEGIN;

-- Cách tính ngưỡng bậc phí mua hộ — chỉ có ý nghĩa khi merchant_type = 'buy_on_behalf'.
ALTER TABLE merchants ADD COLUMN buy_on_behalf_fee_basis VARCHAR(10);
ALTER TABLE merchants ADD CONSTRAINT merchants_fee_basis_valid
  CHECK (buy_on_behalf_fee_basis IS NULL OR buy_on_behalf_fee_basis IN ('quantity', 'value'));
COMMENT ON COLUMN merchants.buy_on_behalf_fee_basis IS
  'Ngưỡng bậc phí mua hộ tính theo gì — ''quantity'' (tổng số lượng sản phẩm cả đơn) hoặc
  ''value'' (giá trị đơn hàng, subtotal). Chỉ dùng khi merchant_type = ''buy_on_behalf''';

CREATE TABLE merchant_fee_tiers (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id       UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  min_threshold     INTEGER NOT NULL,   -- số lượng sản phẩm hoặc VNĐ, tuỳ merchants.buy_on_behalf_fee_basis
  max_threshold     INTEGER,            -- NULL = không giới hạn trên
  fee_type          VARCHAR(10) NOT NULL,
  fee_fixed_amount  INTEGER,            -- VNĐ — bắt buộc khi fee_type = 'fixed'
  fee_percent       NUMERIC(5,2),       -- % giá trị đơn — bắt buộc khi fee_type = 'percent'
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT merchant_fee_tiers_threshold_valid CHECK (
    min_threshold >= 0 AND (max_threshold IS NULL OR max_threshold >= min_threshold)
  ),
  CONSTRAINT merchant_fee_tiers_type_valid CHECK (fee_type IN ('fixed', 'percent')),
  CONSTRAINT merchant_fee_tiers_amount_valid CHECK (
    (fee_type = 'fixed'    AND fee_fixed_amount IS NOT NULL AND fee_fixed_amount >= 0 AND fee_percent IS NULL)
    OR
    (fee_type = 'percent'  AND fee_percent IS NOT NULL AND fee_percent >= 0 AND fee_percent <= 100 AND fee_fixed_amount IS NULL)
  ),
  UNIQUE (merchant_id, min_threshold)
);
COMMENT ON TABLE merchant_fee_tiers IS
  'Bậc phí mua hộ theo cửa hàng — admin cấu hình lúc tạo/sửa cửa hàng ở web admin (khác
  wholesale_tiers, do chủ cửa hàng tự cấu hình). Chỉ áp dụng khi merchants.merchant_type =
  ''buy_on_behalf''. create_order() tự chọn bậc có min_threshold cao nhất còn thoả ngưỡng
  (số lượng hoặc giá trị đơn, tuỳ buy_on_behalf_fee_basis) rồi tính phí — không tin số phí
  client gửi.';
CREATE INDEX idx_merchant_fee_tiers_merchant ON merchant_fee_tiers (merchant_id, min_threshold);

-- Khoản phí mua hộ cộng vào tổng thanh toán — tách riêng cột thay vì gộp vào tax_amount để
-- hiển thị rõ ràng ở cả admin lẫn app khách, giống tinh thần delivery_fee/discount_amount.
ALTER TABLE orders ADD COLUMN buy_on_behalf_fee INTEGER NOT NULL DEFAULT 0;
ALTER TABLE orders DROP CONSTRAINT orders_amounts_not_negative;
ALTER TABLE orders ADD CONSTRAINT orders_amounts_not_negative CHECK (
  subtotal >= 0 AND delivery_fee >= 0 AND discount_amount >= 0
  AND tax_amount >= 0 AND total_amount >= 0 AND buy_on_behalf_fee >= 0
);
ALTER TABLE orders DROP CONSTRAINT orders_total_matches;
ALTER TABLE orders ADD CONSTRAINT orders_total_matches CHECK (
  total_amount = subtotal + delivery_fee + tax_amount + buy_on_behalf_fee - discount_amount
);

-- create_order(): thêm bước tự tính buy_on_behalf_fee theo merchant_type/fee_basis/
-- merchant_fee_tiers ngay trước khi insert orders — chữ ký hàm giữ nguyên (không thêm
-- tham số), vì phí này KHÔNG do client quyết định, chỉ suy ra từ cấu hình cửa hàng.
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
  v_merchant_type merchant_type;
  v_fee_basis     VARCHAR(10);
  v_fee_tier      RECORD;
  v_buy_on_behalf_fee INTEGER := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND merchant_id = p_merchant_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Chi nhánh không thuộc cửa hàng này' USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Đơn hàng phải có ít nhất 1 món' USING ERRCODE = 'check_violation';
  END IF;

  SELECT commission_rate, merchant_type, buy_on_behalf_fee_basis
    INTO v_commission_rate, v_merchant_type, v_fee_basis
    FROM merchants WHERE id = p_merchant_id;

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

  -- Phí mua hộ (chỉ cửa hàng merchant_type = 'buy_on_behalf') — chọn bậc có min_threshold
  -- cao nhất còn thoả ngưỡng dưới/trên theo basis (số lượng cả đơn hoặc giá trị đơn hàng).
  -- Không tin số phí client gửi (không có tham số nào cho việc này) — luôn tự tính lại.
  IF v_merchant_type = 'buy_on_behalf' THEN
    SELECT * INTO v_fee_tier FROM merchant_fee_tiers
     WHERE merchant_id = p_merchant_id
       AND min_threshold <= (CASE WHEN v_fee_basis = 'value' THEN v_subtotal ELSE v_order_quantity_total END)
       AND (max_threshold IS NULL OR max_threshold >= (CASE WHEN v_fee_basis = 'value' THEN v_subtotal ELSE v_order_quantity_total END))
     ORDER BY min_threshold DESC
     LIMIT 1;

    IF FOUND THEN
      v_buy_on_behalf_fee := CASE
        WHEN v_fee_tier.fee_type = 'fixed' THEN v_fee_tier.fee_fixed_amount
        ELSE ROUND(v_subtotal * v_fee_tier.fee_percent / 100.0)
      END;
    END IF;
  END IF;

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
    subtotal, delivery_fee, discount_amount, tax_amount, buy_on_behalf_fee, total_amount,
    commission_amount, merchant_payout,
    payment_method, payment_status, scheduled_for, customer_note
  ) VALUES (
    p_customer_id, p_merchant_id, p_branch_id, p_sales_model,
    (CASE WHEN p_payment_method = 'cod' THEN 'placed' ELSE 'pending_payment' END)::order_status,
    p_ship_recipient_name, p_ship_recipient_phone, p_ship_line1, p_ship_ward, p_ship_district,
    p_ship_province, p_ship_latitude, p_ship_longitude, p_ship_note,
    v_subtotal, p_delivery_fee, v_discount, p_tax_amount, v_buy_on_behalf_fee,
    v_subtotal + p_delivery_fee + p_tax_amount + v_buy_on_behalf_fee - v_discount,
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
  'Tạo đơn: chốt giá qua resolve_variant_price (bậc giá sỉ theo số lượng riêng món; bậc đặt trước theo tổng số lượng cả đơn + số ngày/tuần riêng món, chỉ xét đúng loại bậc theo order_kind của từng món; không khớp thì giá gốc), giữ chỗ tồn kho, áp NHIỀU voucher cùng lúc (tối đa voucher_settings.max_vouchers_per_order), tự tính phí mua hộ theo merchant_fee_tiers nếu merchant_type = buy_on_behalf — tất cả trong 1 transaction';

COMMIT;
