-- ============================================================================
-- MIGRATION 94 — SỬA LỖI NGHIÊM TRỌNG: create_order() mất hẳn phần tính VAT/TNCN từ migration
-- 84 (hofa-db/84_instant_scheduled_order.sql).
--
-- Nguyên nhân: migration 84 viết CREATE OR REPLACE FUNCTION create_order dựa trên bản CŨ hơn
-- (trước migration 67/81 thêm vat_amount/pit_amount), rồi tự nhận nhầm "thân hàm còn lại giữ
-- nguyên" — thực tế đã VÔ TÌNH XOÁ MẤT toàn bộ phần lấy vat_rate/pit_rate của cửa hàng, tính
-- v_vat_amount/v_pit_amount, và trừ 2 khoản này vào merchant_payout. Từ lúc migration 84 chạy,
-- MỌI đơn tạo mới đều có vat_amount=0, pit_amount=0 (dùng DEFAULT của cột) dù cửa hàng có cấu
-- hình vat_rate/pit_rate khác 0 — cửa hàng bị "quên trừ thuế", ví cộng dư đúng bằng phần thuế
-- lẽ ra phải trừ, và màn Tài chính (GET /merchants/:id/finance/summary) hiện đúng 0đ dù nhãn %
-- vẫn hiện tỷ lệ hiện tại của cửa hàng (số 0 lấy thẳng từ o.vat_amount/o.pit_amount đã sai từ
-- lúc tạo đơn, % lấy riêng từ merchants.vat_rate/pit_rate hiện tại — 2 nguồn khác nhau nên
-- không khớp, đúng như cửa hàng phản ánh: nhãn "Thuế GTGT (3%)" nhưng số tiền lại "-0đ").
--
-- Cách sửa — giống hệt cách migration 68 đã hồi tố hồi trước migration 67 ra đời:
-- 1) CREATE OR REPLACE lại create_order, giữ NGUYÊN mọi phần migration 84 đã thêm (đơn giao
--    ngay đặt trước "ngủ"/"nổ"), cộng thêm lại đúng phần tính VAT/TNCN đã mất.
-- 2) Backfill vat_amount/pit_amount/merchant_payout cho MỌI đơn đang bị 0/0 (dùng vat_rate/
--    pit_rate HIỆN TẠI của cửa hàng — không có lịch sử tỷ lệ để chính xác hơn, cùng cách xấp xỉ
--    68 đã dùng). An toàn với đơn cửa hàng thật sự có tỷ lệ 0% (ROUND(x*0/100)=0, không đổi gì).
-- 3) Với đơn đã 'delivered' (đã cộng ví bằng số CŨ, thiếu phần thuế) — chèn thêm dòng sổ cái
--    entry_type=tax_correction, amount ÂM đúng phần vừa backfill, KHÔNG sửa/xoá dòng cũ.
--
-- CẢNH BÁO trước khi chạy: bước 3 làm giảm số dư ví thật của cửa hàng đang có đơn ảnh hưởng —
-- kiểm tra cửa hàng nào bị âm ví sau khi chạy bằng query cuối file trước khi cho rút tiếp.
-- ============================================================================

BEGIN;

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
  v_vat_rate      NUMERIC;
  v_pit_rate      NUMERIC;
  v_vat_amount    INTEGER;
  v_pit_amount    INTEGER;
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
  v_prep_settings RECORD;
  v_prep_tier     INTEGER;
  v_default_prep_minutes INTEGER;
  v_branch_auto_accept BOOLEAN;
  v_confirm_sweep_deadline TIMESTAMPTZ;
  v_scheduled_activated_at TIMESTAMPTZ;
  v_order_kind    TEXT;
  v_concurrent_count INTEGER;
  v_tier_discount_value INTEGER;
  v_tier_max_discount   INTEGER;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND merchant_id = p_merchant_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Chi nhánh không thuộc cửa hàng này' USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Đơn hàng phải có ít nhất 1 món' USING ERRCODE = 'check_violation';
  END IF;

  SELECT commission_rate, vat_rate, pit_rate, merchant_type, buy_on_behalf_fee_basis
    INTO v_commission_rate, v_vat_rate, v_pit_rate, v_merchant_type, v_fee_basis
    FROM merchants WHERE id = p_merchant_id;

  SELECT auto_accept_orders INTO v_branch_auto_accept FROM branches WHERE id = p_branch_id;
  -- Đơn đặt trước/giá sỉ luôn coi như chi nhánh đang TẮT tự động nhận đơn — bắt cửa hàng xác
  -- nhận thủ công cho loại đơn này dù cấu hình thật của chi nhánh là gì.
  IF p_sales_model = 'scheduled' THEN
    v_branch_auto_accept := false;
  END IF;

  -- Tổng số phần của CẢ đơn (gộp mọi sản phẩm) — dùng để so bậc "đặt trước"
  -- (lead_time_days > 0), vì bậc đó tính theo tổng số phần đặt trong cùng 1 lần giao,
  -- không phân biệt đặt món gì.
  SELECT COALESCE(SUM((elem->>'quantity')::INTEGER), 0) INTO v_order_quantity_total
    FROM jsonb_array_elements(p_items) elem;

  -- Loại đơn (dùng lọc điều kiện voucher applicable_order_kinds, xem
  -- hofa-db/50_voucher_conditions.sql) — instant nếu sales_model=instant, ngược lại lấy
  -- order_kind của món ĐẦU TIÊN (mọi món trong 1 đơn luôn cùng order_kind, xem
  -- CartItem/checkout_screen.dart app khách — 1 lần đặt nhiều ngày tách thành nhiều đơn
  -- riêng ở client trước khi gọi hàm này, mỗi đơn vẫn chỉ 1 order_kind).
  IF p_sales_model = 'instant' THEN
    v_order_kind := 'instant';
  ELSE
    SELECT COALESCE(elem->>'order_kind', 'preorder') INTO v_order_kind
    FROM jsonb_array_elements(p_items) elem LIMIT 1;
  END IF;

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

      -- Loại đơn — NULL nghĩa là áp dụng mọi loại, có giá trị thì order_kind của đơn này
      -- phải nằm trong mảng.
      IF v_voucher.applicable_order_kinds IS NOT NULL AND NOT (v_order_kind = ANY(v_voucher.applicable_order_kinds)) THEN
        RAISE EXCEPTION 'Mã % không áp dụng cho loại đơn này', v_voucher_code USING ERRCODE = 'check_violation';
      END IF;

      -- Loại cửa hàng.
      IF v_voucher.applicable_merchant_types IS NOT NULL AND NOT (v_merchant_type::text = ANY(v_voucher.applicable_merchant_types)) THEN
        RAISE EXCEPTION 'Mã % không áp dụng cho loại cửa hàng này', v_voucher_code USING ERRCODE = 'check_violation';
      END IF;

      -- Số đơn khách đang có cùng lúc (tính cả đơn đang tạo này, +1) ở trạng thái CHƯA tới
      -- delivering — không lưu trạng thái riêng, "reset" tự nhiên khi 1 đơn đạt delivering vì
      -- lúc đó nó không còn khớp điều kiện NOT IN nữa (xem comment cột min_concurrent_orders).
      IF v_voucher.min_concurrent_orders IS NOT NULL THEN
        SELECT COUNT(*) + 1 INTO v_concurrent_count FROM orders
         WHERE customer_id = p_customer_id
           AND status NOT IN ('delivering', 'delivered', 'completed', 'cancelled', 'refunded');
        IF v_concurrent_count < v_voucher.min_concurrent_orders THEN
          RAISE EXCEPTION 'Mã % yêu cầu tối thiểu % đơn cùng lúc chưa giao', v_voucher_code, v_voucher.min_concurrent_orders
            USING ERRCODE = 'check_violation';
        END IF;
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

      -- Bậc giảm giá theo giá trị đơn (nếu voucher có cấu hình voucher_amount_tiers) — chọn
      -- bậc min_order_amount cao nhất đơn đạt được, dùng discount_value/max_discount của bậc
      -- đó thay cho của voucher; không có bậc nào khớp (hoặc voucher không có bậc) thì
      -- v_tier_discount_value/v_tier_max_discount ở lại NULL, COALESCE rơi về giá trị voucher
      -- gốc như trước — tương thích ngược với voucher không có bậc.
      v_tier_discount_value := NULL;
      v_tier_max_discount := NULL;
      IF v_voucher.discount_type IN ('percent', 'fixed') THEN
        SELECT discount_value, max_discount INTO v_tier_discount_value, v_tier_max_discount
        FROM voucher_amount_tiers
        WHERE voucher_id = v_voucher.id AND min_order_amount <= v_subtotal
        ORDER BY min_order_amount DESC LIMIT 1;
      END IF;

      IF v_voucher.discount_type = 'percent' THEN
        v_voucher_discount := ROUND(v_subtotal * COALESCE(v_tier_discount_value, v_voucher.discount_value) / 100.0);
        IF COALESCE(v_tier_max_discount, v_voucher.max_discount) IS NOT NULL THEN
          v_voucher_discount := LEAST(v_voucher_discount, COALESCE(v_tier_max_discount, v_voucher.max_discount));
        END IF;
      ELSIF v_voucher.discount_type = 'fixed' THEN
        v_voucher_discount := COALESCE(v_tier_discount_value, v_voucher.discount_value);
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

  -- Bậc thời gian chuẩn bị mặc định — lấy bậc LỚN HƠN trong 2 cách tính (số phần / giá trị),
  -- đơn nào chạm mốc nào trước thì tính theo bậc đó (xem comment ở đầu file migration 39).
  -- Cũng chốt luôn confirm_sweep_deadline ở đây — cùng 1 hàng auto_accept_settings, tuỳ
  -- v_branch_auto_accept (đã ép về false phía trên nếu là đơn đặt trước/giá sỉ).
  SELECT * INTO v_prep_settings FROM auto_accept_settings ORDER BY updated_at DESC LIMIT 1;
  IF FOUND THEN
    v_prep_tier := GREATEST(
      v_order_quantity_total / NULLIF(v_prep_settings.prep_tier_items, 0),
      v_subtotal / NULLIF(v_prep_settings.prep_tier_value_vnd, 0)
    );
    v_default_prep_minutes := LEAST(
      v_prep_settings.prep_default_base_minutes
        + v_prep_settings.prep_default_increment_minutes * COALESCE(v_prep_tier, 0),
      v_prep_settings.prep_default_max_minutes
    );
    v_confirm_sweep_deadline := now() + (
      CASE WHEN v_branch_auto_accept
           THEN v_prep_settings.confirm_sweep_seconds
           ELSE v_prep_settings.manual_confirm_sweep_seconds
      END
    ) * INTERVAL '1 second';
  ELSE
    v_default_prep_minutes := 15; -- chưa từng chạy migration auto_accept_settings
    v_confirm_sweep_deadline := now() + INTERVAL '10 seconds';
  END IF;

  -- Đơn giao ngay đặt trước (sales_model=instant, có scheduled_for) — còn xa (chưa tới ngưỡng
  -- default_prep_minutes trước giờ giao) thì "ngủ": bỏ confirm_sweep_deadline vừa tính ở trên
  -- (NULL), chưa báo cửa hàng (xem POST /orders). Đặt gấp (ngưỡng đã tới ngay lúc đặt) thì giữ
  -- nguyên confirm_sweep_deadline vừa tính, coi như tức thời, đánh dấu đã "nổ" luôn.
  v_scheduled_activated_at := NULL;
  IF p_sales_model = 'instant' AND p_scheduled_for IS NOT NULL THEN
    IF p_scheduled_for - (v_default_prep_minutes || ' minutes')::interval > now() THEN
      v_confirm_sweep_deadline := NULL;
    ELSE
      v_scheduled_activated_at := now();
    END IF;
  END IF;

  -- Chốt VAT/TNCN ước tính CÙNG LÚC với commission_amount — trừ luôn vào merchant_payout để ví
  -- cửa hàng cộng đúng thu nhập ròng (xem hofa-db/67_merchant_net_income_wallet.sql). ĐÂY LÀ
  -- PHẦN đã bị migration 84 vô tình xoá mất, migration 94 này khôi phục lại.
  v_vat_amount := ROUND(v_subtotal * v_vat_rate / 100.0);
  v_pit_amount := ROUND(v_subtotal * v_pit_rate / 100.0);

  -- Bước 2: giờ mới insert orders — MỘT LẦN DUY NHẤT, với số liệu đã chốt xong,
  -- để khớp ngay từ đầu với CHECK orders_total_matches.
  INSERT INTO orders (
    customer_id, merchant_id, branch_id, sales_model, order_kind, status,
    ship_recipient_name, ship_recipient_phone, ship_line1, ship_ward, ship_district,
    ship_province, ship_latitude, ship_longitude, ship_note,
    subtotal, delivery_fee, discount_amount, tax_amount, buy_on_behalf_fee, total_amount,
    commission_amount, vat_amount, pit_amount, merchant_payout,
    payment_method, payment_status, scheduled_for, customer_note, default_prep_minutes,
    confirm_sweep_deadline, scheduled_activated_at
  ) VALUES (
    p_customer_id, p_merchant_id, p_branch_id, p_sales_model, v_order_kind,
    (CASE WHEN p_payment_method = 'cod' THEN 'placed' ELSE 'pending_payment' END)::order_status,
    p_ship_recipient_name, p_ship_recipient_phone, p_ship_line1, p_ship_ward, p_ship_district,
    p_ship_province, p_ship_latitude, p_ship_longitude, p_ship_note,
    v_subtotal, p_delivery_fee, v_discount, p_tax_amount, v_buy_on_behalf_fee,
    v_subtotal + p_delivery_fee + p_tax_amount + v_buy_on_behalf_fee - v_discount,
    ROUND(v_subtotal * v_commission_rate / 100.0), v_vat_amount, v_pit_amount,
    v_subtotal - ROUND(v_subtotal * v_commission_rate / 100.0) - v_vat_amount - v_pit_amount,
    p_payment_method, 'pending', p_scheduled_for, p_customer_note, v_default_prep_minutes,
    v_confirm_sweep_deadline, v_scheduled_activated_at
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
  'Tạo đơn: chốt giá qua resolve_variant_price, giữ chỗ tồn kho, áp NHIỀU voucher cùng lúc, tự tính phí mua hộ nếu buy_on_behalf, tự chốt VAT/TNCN + default_prep_minutes + confirm_sweep_deadline theo bậc/thông số auto_accept_settings — đơn giao ngay có scheduled_for (đặt trước ở màn thanh toán) còn xa thì để confirm_sweep_deadline NULL (ngủ, chưa báo cửa hàng) và scheduled_activated_at NULL, đặt gấp thì đánh dấu scheduled_activated_at=now() luôn — tất cả trong 1 transaction';

-- Bước 1 (hồi tố): backfill vat_amount/pit_amount/merchant_payout cho MỌI đơn đang bị 0/0 —
-- dùng vat_rate/pit_rate HIỆN TẠI của cửa hàng (không có lịch sử tỷ lệ để chính xác hơn).
UPDATE orders o
   SET vat_amount = ROUND(o.subtotal * m.vat_rate / 100.0),
       pit_amount = ROUND(o.subtotal * m.pit_rate / 100.0),
       merchant_payout = o.subtotal - o.commission_amount
                          - ROUND(o.subtotal * m.vat_rate / 100.0)
                          - ROUND(o.subtotal * m.pit_rate / 100.0)
  FROM merchants m
 WHERE o.merchant_id = m.id
   AND o.vat_amount = 0
   AND o.pit_amount = 0;

-- Bước 2 (hồi tố): bù trừ ví cho đơn đã 'delivered' TRƯỚC khi sửa (đã cộng ví bằng số cũ,
-- thiếu phần thuế) — entry_type=tax_correction đã được thêm vào CHECK constraint từ migration
-- 68, không cần ALTER lại. NOT EXISTS guard tránh tạo trùng nếu chạy lại migration này.
INSERT INTO merchant_wallet_transactions (merchant_id, entry_type, amount, order_id, note)
SELECT o.merchant_id, 'tax_correction', -(o.vat_amount + o.pit_amount), o.id,
       'Hồi tố khấu trừ VAT/TNCN cho đơn đã cộng ví thiếu thuế do lỗi migration 84 (xem hofa-db/94_fix_create_order_missing_tax.sql)'
  FROM orders o
  JOIN merchant_wallet_transactions t ON t.order_id = o.id AND t.entry_type = 'order_payout'
 WHERE (o.vat_amount + o.pit_amount) > 0
   AND NOT EXISTS (
     SELECT 1 FROM merchant_wallet_transactions tc
      WHERE tc.order_id = o.id AND tc.entry_type = 'tax_correction'
   );

COMMIT;

-- Chạy riêng (SAU khi COMMIT ở trên) để kiểm tra cửa hàng nào bị âm ví sau khi hồi tố —
-- không tự chặn gì, chỉ để biết trước khi cho phép các cửa hàng đó rút tiền tiếp:
--   SELECT merchant_id, balance FROM merchant_wallet_balances WHERE balance < 0;
