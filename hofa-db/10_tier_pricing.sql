-- ============================================================================
-- Chốt giá đơn hàng theo bậc giá sỉ/đặt trước (wholesale_tiers) thay vì luôn dùng giá
-- bán gốc product_variants.price. Chạy 1 lần trên Supabase SQL Editor.
--
-- Trước đây create_order() bỏ qua hoàn toàn wholesale_tiers, luôn tính tiền theo
-- product_variants.price — khách xem trang sản phẩm thấy giá theo bậc (tính ở client,
-- chỉ để hiển thị) nhưng lúc đặt hàng lại bị tính giá bán gốc, sai với giá đã xem.
-- resolve_variant_price() sửa lại: khớp bậc theo số lượng (và số ngày đặt trước tối
-- thiểu nếu bậc đó có lead_time_days > 0), không có bậc nào khớp thì dùng lại giá gốc.
-- ============================================================================

CREATE OR REPLACE FUNCTION resolve_variant_price(
  p_variant_id UUID, p_quantity INTEGER, p_scheduled_for TIMESTAMPTZ, p_base_price INTEGER
) RETURNS INTEGER AS $$
DECLARE
  v_lead_days INTEGER;
  v_price     INTEGER;
BEGIN
  v_lead_days := CASE WHEN p_scheduled_for IS NULL THEN NULL
                      ELSE GREATEST(FLOOR(EXTRACT(EPOCH FROM (p_scheduled_for - now())) / 86400)::INTEGER, 0)
                 END;

  SELECT unit_price INTO v_price
    FROM wholesale_tiers
   WHERE variant_id = p_variant_id
     AND p_quantity >= min_quantity
     AND (max_quantity IS NULL OR p_quantity <= max_quantity)
     AND (lead_time_days = 0 OR (v_lead_days IS NOT NULL AND v_lead_days >= lead_time_days))
   ORDER BY min_quantity DESC, lead_time_days DESC
   LIMIT 1;

  RETURN COALESCE(v_price, p_base_price);
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION resolve_variant_price IS
  'Chốt giá thật theo bậc giá sỉ/đặt trước khớp số lượng (và số ngày đặt trước nếu có) — không có bậc nào khớp thì trả về giá bán gốc';

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
BEGIN
  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND merchant_id = p_merchant_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Chi nhánh không thuộc cửa hàng này' USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Đơn hàng phải có ít nhất 1 món' USING ERRCODE = 'check_violation';
  END IF;

  SELECT commission_rate INTO v_commission_rate FROM merchants WHERE id = p_merchant_id;

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

    v_unit_price := resolve_variant_price(
      v_variant.id, (v_item->>'quantity')::INTEGER, p_scheduled_for, v_variant.price
    );
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
      'note', v_item->>'note'
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

  -- Bước 3: giờ mới ghi order_items, dùng order.id vừa có
  INSERT INTO order_items (order_id, variant_id, product_name, variant_name, sku, unit, unit_price, quantity, line_total, note)
  SELECT
    v_order.id, (elem->>'variant_id')::UUID, elem->>'product_name', elem->>'variant_name', elem->>'sku',
    elem->>'unit', (elem->>'unit_price')::INTEGER, (elem->>'quantity')::INTEGER, (elem->>'line_total')::INTEGER, elem->>'note'
  FROM jsonb_array_elements(v_items_json) elem;

  IF p_voucher_code IS NOT NULL THEN
    INSERT INTO voucher_redemptions (voucher_id, user_id, order_id, discount_amount)
    VALUES (v_voucher.id, p_customer_id, v_order.id, v_discount);
  END IF;

  RETURN v_order;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION create_order IS
  'Tạo đơn: chốt giá qua resolve_variant_price (bậc giá sỉ/đặt trước, không khớp thì giá gốc), giữ chỗ tồn kho, áp voucher — tất cả trong 1 transaction';
