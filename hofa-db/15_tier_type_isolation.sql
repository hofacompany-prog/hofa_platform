-- ============================================================================
-- MIGRATION 15 — Cách ly bậc giá theo đúng loại (giá sỉ / đặt trước) khi chốt giá
--
-- Từ migration 14, 1 biến thể được phép có CẢ bậc giá sỉ (min_days_per_week = 0) lẫn bậc
-- đặt trước (min_days_per_week > 0) cùng lúc. resolve_variant_price() trước đó tự suy ra
-- loại bậc áp dụng dựa trên số lượng/số ngày — nhưng vậy thì 1 đơn "Giá sỉ" (không có
-- lịch giao theo thứ trong tuần) vẫn có thể vô tình khớp trúng 1 bậc "Đặt trước" nếu tổng
-- số lượng đủ lớn, và ngược lại — hai loại bậc giá cần tách biệt hẳn theo đúng tab khách
-- đang mua (Giá sỉ / Đặt trước), không được lẫn giá của tab kia.
--
-- resolve_variant_price() nhận thêm p_is_preorder — true thì CHỈ xét bậc đặt trước
-- (min_days_per_week > 0), false thì CHỈ xét bậc giá sỉ (min_days_per_week = 0). Giá trị
-- này lấy từ order_kind của từng món trong p_items ("wholesale" | "preorder", client gửi
-- theo đúng tab khách đã thêm vào giỏ — xem CartItem.orderKind phía app khách).
--
-- Chạy 1 lần trên Supabase SQL Editor. Đã gộp vào hofa-db/04_api_functions.sql cho lần
-- dựng DB mới từ đầu.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS resolve_variant_price(UUID, INTEGER, INTEGER, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION resolve_variant_price(
  p_variant_id UUID, p_quantity INTEGER, p_order_quantity INTEGER, p_days_count INTEGER,
  p_is_preorder BOOLEAN, p_base_price INTEGER
) RETURNS INTEGER AS $$
DECLARE
  v_price INTEGER;
BEGIN
  SELECT
    CASE WHEN r.qty_met AND r.days_met THEN r.unit_price_both
         WHEN r.qty_met THEN r.unit_price
         ELSE r.unit_price_days
    END INTO v_price
  FROM (
    SELECT
      t.unit_price, t.unit_price_days, t.unit_price_both,
      t.min_quantity, t.min_days_per_week,
      (CASE WHEN t.min_days_per_week = 0 THEN p_quantity ELSE p_order_quantity END) >= t.min_quantity
        AND (t.max_quantity IS NULL
             OR (CASE WHEN t.min_days_per_week = 0 THEN p_quantity ELSE p_order_quantity END) <= t.max_quantity)
        AS qty_met,
      (t.min_days_per_week > 0 AND p_days_count >= t.min_days_per_week) AS days_met
    FROM wholesale_tiers t
    WHERE t.variant_id = p_variant_id
      AND (t.min_days_per_week > 0) = p_is_preorder
  ) r
  WHERE r.qty_met OR r.days_met
  ORDER BY r.min_quantity DESC, r.min_days_per_week DESC
  LIMIT 1;

  RETURN COALESCE(v_price, p_base_price);
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION resolve_variant_price IS
  'Chốt giá thật theo bậc giá — p_is_preorder=false chỉ xét bậc giá sỉ (so số lượng riêng món), true chỉ xét bậc đặt trước (so tổng số lượng cả lần giao VÀ số ngày/tuần riêng món) — không có bậc nào khớp thì trả về giá bán gốc';

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
  p_voucher_code     VARCHAR DEFAULT NULL,
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
  v_voucher       vouchers;
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
  -- (min_days_per_week > 0), vì bậc đó tính theo tổng số phần đặt trong cùng 1 lần giao,
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

  -- Áp mã giảm giá (nếu có)
  IF p_voucher_code IS NOT NULL THEN
    SELECT * INTO v_voucher FROM vouchers
     WHERE code = p_voucher_code AND is_active
       AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now())
       AND (merchant_id IS NULL OR merchant_id = p_merchant_id)
     FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Mã giảm giá không hợp lệ hoặc đã hết hạn' USING ERRCODE = 'check_violation';
    END IF;

    IF v_subtotal < v_voucher.min_order_amount THEN
      RAISE EXCEPTION 'Đơn chưa đạt giá trị tối thiểu % để dùng mã này', v_voucher.min_order_amount
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_voucher.usage_limit IS NOT NULL AND v_voucher.used_count >= v_voucher.usage_limit THEN
      RAISE EXCEPTION 'Mã giảm giá đã hết lượt dùng' USING ERRCODE = 'check_violation';
    END IF;

    SELECT COUNT(*) INTO v_user_redemptions FROM voucher_redemptions
     WHERE voucher_id = v_voucher.id AND user_id = p_customer_id;
    IF v_user_redemptions >= v_voucher.usage_limit_per_user THEN
      RAISE EXCEPTION 'Bạn đã dùng hết lượt cho mã này' USING ERRCODE = 'check_violation';
    END IF;

    IF v_voucher.discount_type = 'percent' THEN
      v_discount := ROUND(v_subtotal * v_voucher.discount_value / 100.0);
      IF v_voucher.max_discount IS NOT NULL THEN
        v_discount := LEAST(v_discount, v_voucher.max_discount);
      END IF;
    ELSIF v_voucher.discount_type = 'fixed' THEN
      v_discount := v_voucher.discount_value;
    ELSIF v_voucher.discount_type = 'free_shipping' THEN
      v_discount := p_delivery_fee;
    END IF;

    v_discount := LEAST(v_discount, v_subtotal + p_delivery_fee); -- không cho âm tiền

    UPDATE vouchers SET used_count = used_count + 1 WHERE id = v_voucher.id;
  END IF;

  -- Bước 2: giờ mới insert orders — MỘT LẦN DUY NHẤT, với số liệu đã chốt xong,
  -- để khớp ngay từ đầu với CHECK orders_total_matches.
  INSERT INTO orders (
    customer_id, merchant_id, branch_id, sales_model, status,
    ship_recipient_name, ship_recipient_phone, ship_line1, ship_ward, ship_district,
    ship_province, ship_latitude, ship_longitude, ship_note,
    subtotal, delivery_fee, discount_amount, tax_amount, total_amount,
    commission_amount, merchant_payout, voucher_code,
    payment_method, payment_status, scheduled_for, customer_note
  ) VALUES (
    p_customer_id, p_merchant_id, p_branch_id, p_sales_model,
    (CASE WHEN p_payment_method = 'cod' THEN 'placed' ELSE 'pending_payment' END)::order_status,
    p_ship_recipient_name, p_ship_recipient_phone, p_ship_line1, p_ship_ward, p_ship_district,
    p_ship_province, p_ship_latitude, p_ship_longitude, p_ship_note,
    v_subtotal, p_delivery_fee, v_discount, p_tax_amount, v_subtotal + p_delivery_fee + p_tax_amount - v_discount,
    ROUND(v_subtotal * v_commission_rate / 100.0), v_subtotal - ROUND(v_subtotal * v_commission_rate / 100.0), p_voucher_code,
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

  IF p_voucher_code IS NOT NULL THEN
    INSERT INTO voucher_redemptions (voucher_id, user_id, order_id, discount_amount)
    VALUES (v_voucher.id, p_customer_id, v_order.id, v_discount);
  END IF;

  RETURN v_order;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION create_order IS
  'Tạo đơn: chốt giá qua resolve_variant_price (bậc giá sỉ theo số lượng riêng món; bậc đặt trước theo tổng số lượng cả đơn + số ngày/tuần riêng món, chỉ xét đúng loại bậc theo order_kind của từng món; không khớp thì giá gốc), giữ chỗ tồn kho, áp voucher — tất cả trong 1 transaction';

COMMIT;
