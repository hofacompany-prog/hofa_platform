-- ============================================================================
-- MIGRATION 108 — Cộng % phí mua hộ THẲNG vào giá món (không còn hiện dòng "phí mua hộ" riêng ở
-- thanh toán/đơn hàng) + thêm phí đơn nhỏ/lẻ áp dụng toàn sàn.
--
-- 1) Phí mua hộ (merchant_fee_tiers, chỉ merchant_type='buy_on_behalf'):
--    - Bậc kiểu 'percent' — % giờ được CỘNG THẲNG vào unit_price/line_total của từng món trong
--      order_items, và orders.subtotal = tổng các dòng ĐÃ cộng % (khách thấy/trả đúng giá này).
--      orders.buy_on_behalf_fee vẫn lưu đúng số tiền phí (dùng cho driver fee-share, xem
--      hofa-db/79_driver_buy_on_behalf_fee_share.sql) — chỉ đổi VAI TRÒ: không còn cộng thêm 1 lần
--      nữa vào total_amount (đã nằm sẵn trong subtotal), tránh tính đôi.
--    - Bậc kiểu 'fixed' — TẠM NGỪNG áp dụng (fee=0) theo yêu cầu "giữ cấu hình, chưa dùng tới,
--      dùng lại sau". Không xoá cột/dữ liệu, chỉ bỏ qua lúc tính.
--    - Hoa hồng/VAT/TNCN cửa hàng (commission_amount/vat_amount/pit_amount/merchant_payout) và
--      tiền hoàn ứng cho tài xế mua hộ (buy_on_behalf_reimbursement) TIẾP TỤC tính trên giá GỐC
--      (trước khi cộng %) — không đổi bản chất chia tiền so với trước, chỉ đổi cách hiển thị giá.
-- 2) Phí đơn nhỏ/lẻ (small_order_fee_settings, MỌI merchant_type): đơn có subtotal (đã gồm % mua
--    hộ nếu có) dưới 1 ngưỡng admin cấu hình thì cộng thêm 1 khoản phí cố định vào total_amount.
--
-- Cả 2 thay đổi trên nằm trong create_order() — hàm PL/pgSQL DUY NHẤT tính toàn bộ tiền đơn lúc
-- tạo đơn, bản trước là hofa-db/94_fix_create_order_missing_tax.sql. Chữ ký GIỮ NGUYÊN (không
-- thêm/bớt tham số) nên không cần DROP trước khi CREATE OR REPLACE.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Bảng cấu hình phí đơn nhỏ/lẻ — mẫu y hệt shipping_fee_settings (1 dòng đang áp dụng).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS small_order_fee_settings (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  is_active        BOOLEAN NOT NULL DEFAULT true,
  threshold_amount INTEGER NOT NULL DEFAULT 30000,  -- "mức tính phí": subtotal DƯỚI ngưỡng này bị tính phí
  fee_amount       INTEGER NOT NULL DEFAULT 5000,   -- "phí" cộng thêm vào total_amount
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by       UUID REFERENCES users(id) ON DELETE SET NULL,

  CONSTRAINT small_order_fee_threshold_valid CHECK (threshold_amount >= 0),
  CONSTRAINT small_order_fee_amount_valid    CHECK (fee_amount >= 0)
);
COMMENT ON TABLE small_order_fee_settings IS
  'Phí cộng thêm cho đơn giá trị nhỏ — áp dụng MỌI cửa hàng (không riêng mua hộ). Đơn có subtotal
   (đã gồm % phí mua hộ nếu có) < threshold_amount thì total_amount cộng thêm fee_amount. Chỉ giữ
   1 dòng đang áp dụng (dòng mới nhất theo updated_at), giống shipping_fee_settings.';

INSERT INTO small_order_fee_settings (is_active, threshold_amount, fee_amount)
SELECT true, 30000, 5000
WHERE NOT EXISTS (SELECT 1 FROM small_order_fee_settings);

ALTER TABLE orders ADD COLUMN IF NOT EXISTS small_order_fee INTEGER NOT NULL DEFAULT 0;
COMMENT ON COLUMN orders.small_order_fee IS
  'Phí đơn nhỏ/lẻ tự tính lúc tạo đơn nếu subtotal dưới ngưỡng small_order_fee_settings — xem
   hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql.';

-- ---------------------------------------------------------------------------
-- 2) Sửa CHECK tổng tiền: bỏ + buy_on_behalf_fee (giờ đã nằm sẵn trong subtotal, cộng lần nữa sẽ
--    tính đôi), thêm + small_order_fee. Đơn không phải mua hộ có buy_on_behalf_fee=0 từ trước nên
--    bỏ số hạng này khỏi công thức không ảnh hưởng gì tới các đơn đó.
-- ---------------------------------------------------------------------------
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_total_matches;
ALTER TABLE orders ADD CONSTRAINT orders_total_matches CHECK (
  total_amount = subtotal + delivery_fee + tax_amount + small_order_fee - discount_amount
);

-- ---------------------------------------------------------------------------
-- 3) create_order() — copy nguyên văn từ migration 94, chỉ sửa đúng phần phí mua hộ/phí đơn nhỏ
--    (đánh dấu === MỚI === ở các đoạn thay đổi). Mọi phần khác (topping, wholesale/preorder tier,
--    voucher, bậc chuẩn bị, VAT/TNCN, order_items) giữ y hệt, chỉ đổi tên biến v_subtotal ->
--    v_base_subtotal ở những chỗ vẫn cần dùng giá trị GỐC (trước khi cộng % mua hộ).
-- ---------------------------------------------------------------------------
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
  v_base_subtotal INTEGER := 0;  -- giá GỐC (trước khi cộng % mua hộ) — dùng cho voucher/bậc chuẩn bị/hoa hồng/thuế
  v_subtotal      INTEGER := 0;  -- giá CUỐI (đã cộng % mua hộ nếu có) — lưu vào orders.subtotal/order_items
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
  v_fee_percent   NUMERIC := 0;   -- === MỚI === % bậc mua hộ khớp (0 nếu không khớp bậc nào HOẶC bậc khớp là 'fixed')
  v_buy_on_behalf_fee INTEGER := 0;
  v_new_items_json JSONB;         -- === MỚI === dùng khi cộng % vào từng dòng order_items
  v_elem_unit_price INTEGER;      -- === MỚI ===
  v_elem_line_total INTEGER;      -- === MỚI ===
  v_small_order_settings RECORD;  -- === MỚI ===
  v_small_order_fee INTEGER := 0; -- === MỚI ===
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

  -- Bước 1: chốt giá GỐC + giữ tồn kho cho từng món. CHƯA insert orders/order_items ở đây,
  -- vì orders có CHECK (total_amount = subtotal + delivery_fee + tax_amount + small_order_fee -
  -- discount_amount) — phải biết subtotal cuối cùng (và cả voucher) trước khi insert được 1 lần
  -- cho khớp ràng buộc.
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
    v_base_subtotal := v_base_subtotal + v_line_total;

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

  -- === MỚI === Phí mua hộ (chỉ cửa hàng merchant_type = 'buy_on_behalf') — chọn bậc có
  -- min_threshold cao nhất còn thoả ngưỡng dưới/trên theo basis (số lượng cả đơn hoặc GIÁ TRỊ GỐC
  -- của đơn hàng — v_base_subtotal, trước khi cộng %). Không tin số phí client gửi (không có
  -- tham số nào cho việc này) — luôn tự tính lại. Bậc kiểu 'fixed' TẠM NGỪNG áp dụng (giữ cấu
  -- hình, chưa dùng tới) — chỉ bậc 'percent' mới thật sự cộng phí, cộng THẲNG vào giá món thay vì
  -- làm 1 dòng phụ riêng như trước.
  IF v_merchant_type = 'buy_on_behalf' THEN
    SELECT * INTO v_fee_tier FROM merchant_fee_tiers
     WHERE merchant_id = p_merchant_id
       AND min_threshold <= (CASE WHEN v_fee_basis = 'value' THEN v_base_subtotal ELSE v_order_quantity_total END)
       AND (max_threshold IS NULL OR max_threshold >= (CASE WHEN v_fee_basis = 'value' THEN v_base_subtotal ELSE v_order_quantity_total END))
     ORDER BY min_threshold DESC
     LIMIT 1;

    IF FOUND AND v_fee_tier.fee_type = 'percent' THEN
      v_fee_percent := COALESCE(v_fee_tier.fee_percent, 0);
    END IF;
  END IF;

  -- === MỚI === Cộng % (nếu có) THẲNG vào unit_price/line_total của từng món — v_subtotal (giá
  -- CUỐI, lưu vào orders.subtotal/order_items) khác v_base_subtotal (giá GỐC, vẫn dùng cho voucher/
  -- bậc chuẩn bị/hoa hồng/thuế bên dưới, KHÔNG đổi). buy_on_behalf_fee suy ra từ chênh lệch sau khi
  -- làm tròn từng dòng (có thể lệch 1-2đ so với ROUND(base*percent/100) 1 lần — không đáng kể) —
  -- vẫn dùng đúng cho driver fee-share (hofa-db/79_driver_buy_on_behalf_fee_share.sql).
  IF v_fee_percent > 0 THEN
    v_new_items_json := '[]'::jsonb;
    v_subtotal := 0;
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_items_json) LOOP
      v_elem_unit_price := ROUND((v_elem->>'unit_price')::NUMERIC * (1 + v_fee_percent / 100.0));
      v_elem_line_total := v_elem_unit_price * (v_elem->>'quantity')::INTEGER;
      v_subtotal := v_subtotal + v_elem_line_total;
      v_new_items_json := v_new_items_json || (
        v_elem || jsonb_build_object('unit_price', v_elem_unit_price, 'line_total', v_elem_line_total)
      );
    END LOOP;
    v_items_json := v_new_items_json;
    v_buy_on_behalf_fee := v_subtotal - v_base_subtotal;
  ELSE
    v_subtotal := v_base_subtotal;
    v_buy_on_behalf_fee := 0;
  END IF;

  -- === MỚI === Phí đơn nhỏ/lẻ — áp dụng MỌI merchant_type, so với subtotal CUỐI (đã gồm % mua hộ
  -- nếu có, đúng số khách thực trả cho hàng).
  SELECT * INTO v_small_order_settings FROM small_order_fee_settings
   WHERE is_active ORDER BY updated_at DESC LIMIT 1;
  IF FOUND AND v_subtotal < v_small_order_settings.threshold_amount THEN
    v_small_order_fee := v_small_order_settings.fee_amount;
  END IF;

  -- Áp mã giảm giá (nếu có) — nhiều mã cùng lúc, tối đa voucher_settings.max_vouchers_per_order.
  -- Dùng v_base_subtotal (giá GỐC) — voucher tính trên giá trị hàng thật, không đổi so với trước.
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

      IF v_base_subtotal < v_voucher.min_order_amount THEN
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
        WHERE voucher_id = v_voucher.id AND min_order_amount <= v_base_subtotal
        ORDER BY min_order_amount DESC LIMIT 1;
      END IF;

      IF v_voucher.discount_type = 'percent' THEN
        v_voucher_discount := ROUND(v_base_subtotal * COALESCE(v_tier_discount_value, v_voucher.discount_value) / 100.0);
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

    v_discount := LEAST(v_discount, v_base_subtotal + p_delivery_fee); -- không cho âm tiền
  END IF;

  -- Bậc thời gian chuẩn bị mặc định — lấy bậc LỚN HƠN trong 2 cách tính (số phần / giá trị),
  -- đơn nào chạm mốc nào trước thì tính theo bậc đó (xem comment ở đầu file migration 39).
  -- Cũng chốt luôn confirm_sweep_deadline ở đây — cùng 1 hàng auto_accept_settings, tuỳ
  -- v_branch_auto_accept (đã ép về false phía trên nếu là đơn đặt trước/giá sỉ).
  SELECT * INTO v_prep_settings FROM auto_accept_settings ORDER BY updated_at DESC LIMIT 1;
  IF FOUND THEN
    v_prep_tier := GREATEST(
      v_order_quantity_total / NULLIF(v_prep_settings.prep_tier_items, 0),
      v_base_subtotal / NULLIF(v_prep_settings.prep_tier_value_vnd, 0)
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
  -- cửa hàng cộng đúng thu nhập ròng (xem hofa-db/67_merchant_net_income_wallet.sql). Dùng
  -- v_base_subtotal (giá GỐC) — phí mua hộ KHÔNG phải doanh thu cửa hàng, không tính hoa hồng/
  -- thuế trên phần đó, y hệt hành vi trước migration này.
  v_vat_amount := ROUND(v_base_subtotal * v_vat_rate / 100.0);
  v_pit_amount := ROUND(v_base_subtotal * v_pit_rate / 100.0);

  -- Bước 2: giờ mới insert orders — MỘT LẦN DUY NHẤT, với số liệu đã chốt xong,
  -- để khớp ngay từ đầu với CHECK orders_total_matches. subtotal dùng v_subtotal (giá CUỐI, đã
  -- cộng % mua hộ nếu có) — đúng số khách thấy/trả cho hàng; commission/vat/pit/merchant_payout
  -- dùng v_base_subtotal (giá GỐC, không đổi so với trước).
  INSERT INTO orders (
    customer_id, merchant_id, branch_id, sales_model, order_kind, status,
    ship_recipient_name, ship_recipient_phone, ship_line1, ship_ward, ship_district,
    ship_province, ship_latitude, ship_longitude, ship_note,
    subtotal, delivery_fee, discount_amount, tax_amount, buy_on_behalf_fee, small_order_fee, total_amount,
    commission_amount, vat_amount, pit_amount, merchant_payout,
    payment_method, payment_status, scheduled_for, customer_note, default_prep_minutes,
    confirm_sweep_deadline, scheduled_activated_at
  ) VALUES (
    p_customer_id, p_merchant_id, p_branch_id, p_sales_model, v_order_kind,
    (CASE WHEN p_payment_method = 'cod' THEN 'placed' ELSE 'pending_payment' END)::order_status,
    p_ship_recipient_name, p_ship_recipient_phone, p_ship_line1, p_ship_ward, p_ship_district,
    p_ship_province, p_ship_latitude, p_ship_longitude, p_ship_note,
    v_subtotal, p_delivery_fee, v_discount, p_tax_amount, v_buy_on_behalf_fee, v_small_order_fee,
    v_subtotal + p_delivery_fee + p_tax_amount + v_small_order_fee - v_discount,
    ROUND(v_base_subtotal * v_commission_rate / 100.0), v_vat_amount, v_pit_amount,
    v_base_subtotal - ROUND(v_base_subtotal * v_commission_rate / 100.0) - v_vat_amount - v_pit_amount,
    p_payment_method, 'pending', p_scheduled_for, p_customer_note, v_default_prep_minutes,
    v_confirm_sweep_deadline, v_scheduled_activated_at
  ) RETURNING * INTO v_order;

  -- Bước 3: giờ mới ghi order_items, dùng order.id vừa có — insert từng dòng (không
  -- bulk) để lấy được id vừa tạo, dùng ghi order_item_toppings tương ứng ngay sau đó.
  -- unit_price/line_total đọc từ v_items_json đã được cộng % ở bước trên (nếu có) — không cần
  -- sửa gì thêm ở vòng lặp này.
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
  'Tạo đơn: chốt giá qua resolve_variant_price, giữ chỗ tồn kho, áp NHIỀU voucher cùng lúc, tự tính
   phí mua hộ nếu buy_on_behalf (bậc % cộng THẲNG vào giá món, bậc fixed tạm không dùng — xem
   hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql), tự tính phí đơn nhỏ toàn sàn nếu
   dưới ngưỡng small_order_fee_settings, tự chốt VAT/TNCN (trên giá GỐC, không gồm % mua hộ) +
   default_prep_minutes + confirm_sweep_deadline theo bậc/thông số auto_accept_settings — đơn giao
   ngay có scheduled_for (đặt trước ở màn thanh toán) còn xa thì để confirm_sweep_deadline NULL
   (ngủ, chưa báo cửa hàng) và scheduled_activated_at NULL, đặt gấp thì đánh dấu
   scheduled_activated_at=now() luôn — tất cả trong 1 transaction';

-- ---------------------------------------------------------------------------
-- 4) update_delivery_status() — copy nguyên văn từ migration 107, chỉ sửa đúng phần hoàn ứng tài
--    xế mua hộ: lấy thêm buy_on_behalf_fee ngay từ đầu hàm, hoàn đúng tiền hàng THẬT (subtotal đã
--    trừ phần % giờ nằm trong đó) thay vì hoàn nguyên subtotal (sẽ hoàn dư đúng bằng phần %).
--    Chữ ký giữ nguyên 7 tham số như migration 107 — không cần DROP.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_delivery_status(
  p_delivery_id UUID,
  p_new_status  delivery_status,
  p_otp         VARCHAR DEFAULT NULL,
  p_recipient_name VARCHAR DEFAULT NULL,
  p_proof_photo_urls JSONB DEFAULT NULL,
  p_signature_url VARCHAR DEFAULT NULL,
  p_failure_reason TEXT DEFAULT NULL
) RETURNS deliveries AS $$
DECLARE
  v_delivery deliveries;
  v_item RECORD;
  v_merchant_type merchant_type;
  v_order_subtotal INTEGER;
  v_order_total_amount INTEGER;
  v_order_buy_on_behalf_fee INTEGER;  -- === MỚI === lấy sớm ngay từ đầu hàm (trước chỉ lấy muộn hơn, dòng dưới)
  v_otp_min_amount INTEGER;
  v_order_payment_method payment_method;
  v_order_total INTEGER;
  v_commission_rate NUMERIC;
  v_vat_rate NUMERIC;
  v_pit_rate NUMERIC;
  v_fee_share_rate NUMERIC;
  v_commission_amount INTEGER;
  v_vat_amount INTEGER;
  v_pit_amount INTEGER;
  v_fee_share_amount INTEGER;
  v_driver_fee_net INTEGER;
  v_has_other_active BOOLEAN;
BEGIN
  SELECT * INTO v_delivery FROM deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy chuyến giao hàng' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT m.merchant_type, o.subtotal, o.total_amount, o.buy_on_behalf_fee
    INTO v_merchant_type, v_order_subtotal, v_order_total_amount, v_order_buy_on_behalf_fee
    FROM orders o JOIN merchants m ON m.id = o.merchant_id
   WHERE o.id = v_delivery.order_id;

  SELECT min_order_amount INTO v_otp_min_amount FROM otp_settings ORDER BY updated_at DESC LIMIT 1;
  v_otp_min_amount := COALESCE(v_otp_min_amount, 0);

  -- Đơn mua hộ: tài xế tự đi mua, không có nhân viên cửa hàng nào đọc OTP lấy hàng cho tài xế
  -- — bỏ OTP ở bước này, bắt buộc ít nhất 1 ảnh hoá đơn/hàng đã mua làm bằng chứng thay thế.
  -- Đơn thường: chỉ bắt buộc đúng OTP nếu đơn VƯỢT ngưỡng otp_settings (đơn giá trị thấp bỏ
  -- qua xác nhận hoàn toàn, xem hofa-db/73_otp_threshold_settings.sql).
  IF p_new_status = 'picked_up' THEN
    IF v_merchant_type = 'buy_on_behalf' THEN
      IF p_proof_photo_urls IS NULL OR jsonb_array_length(p_proof_photo_urls) = 0 THEN
        RAISE EXCEPTION 'Cần ít nhất 1 ảnh hoá đơn/hàng đã mua' USING ERRCODE = 'check_violation';
      END IF;
    ELSIF v_order_total_amount > v_otp_min_amount AND (p_otp IS NULL OR p_otp <> v_delivery.pickup_otp) THEN
      RAISE EXCEPTION 'Mã OTP lấy hàng không đúng' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF p_new_status = 'delivered' AND v_order_total_amount > v_otp_min_amount
     AND (p_otp IS NULL OR p_otp <> v_delivery.delivery_otp) THEN
    RAISE EXCEPTION 'Mã OTP giao hàng không đúng' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE deliveries SET
    status = p_new_status,
    accepted_at      = CASE WHEN p_new_status = 'accepted'      THEN now() ELSE accepted_at END,
    arrived_store_at = CASE WHEN p_new_status = 'arrived_store'  THEN now() ELSE arrived_store_at END,
    picked_up_at     = CASE WHEN p_new_status = 'picked_up'      THEN now() ELSE picked_up_at END,
    delivered_at     = CASE WHEN p_new_status = 'delivered'      THEN now() ELSE delivered_at END,
    recipient_name   = COALESCE(p_recipient_name, recipient_name),
    proof_photo_urls = COALESCE(p_proof_photo_urls, proof_photo_urls),
    signature_url    = COALESCE(p_signature_url, signature_url),
    failure_reason   = CASE WHEN p_new_status = 'failed' THEN p_failure_reason ELSE failure_reason END,
    attempt_count    = CASE WHEN p_new_status = 'failed' THEN attempt_count + 1 ELSE attempt_count END
  WHERE id = p_delivery_id
  RETURNING * INTO v_delivery;

  IF p_new_status = 'accepted' THEN
    -- Tài xế THẬT SỰ xác nhận — đây là lúc DUY NHẤT orders.status được phép chuyển sang
    -- 'assigned' (xem hofa-db/106_driver_confirm_before_assigned.sql). p_force=TRUE vì đơn có
    -- thể đang ở 'ready_for_pickup' (tìm bình thường) hoặc 'confirmed'/'preparing' (tìm sớm).
    PERFORM update_order_status(v_delivery.order_id, 'assigned', NULL, 'driver', NULL, TRUE);
  ELSIF p_new_status = 'picked_up' THEN
    -- Lấy hàng xong: trừ tồn kho thật (on_hand) và bỏ phần đã giữ (reserved) — cửa hàng mua hộ
    -- không có tồn kho thật để trừ (xem hofa-db/77_buy_on_behalf_unlimited_stock.sql). KHÔNG còn
    -- hoàn tiền ứng mua hàng ở bước này nữa (dời sang nhánh 'delivered' bên dưới).
    IF v_merchant_type <> 'buy_on_behalf' THEN
      FOR v_item IN
        SELECT oi.variant_id, oi.quantity FROM order_items oi
         JOIN orders o ON o.id = oi.order_id WHERE o.id = (
           SELECT order_id FROM deliveries WHERE id = p_delivery_id
         )
      LOOP
        IF v_item.variant_id IS NOT NULL THEN
          PERFORM release_inventory(
            (SELECT branch_id FROM orders WHERE id = v_delivery.order_id),
            v_item.variant_id, v_item.quantity
          );
          PERFORM apply_stock_movement(
            (SELECT branch_id FROM orders WHERE id = v_delivery.order_id),
            v_item.variant_id, 'sale_out', -v_item.quantity, 'order', v_delivery.order_id
          );
        END IF;
      END LOOP;
    END IF;
    PERFORM update_order_status(v_delivery.order_id, 'picked_up', NULL, 'driver', NULL, TRUE);
  ELSIF p_new_status = 'delivering' THEN
    PERFORM update_order_status(v_delivery.order_id, 'delivering', NULL, 'driver', NULL, TRUE);
  ELSIF p_new_status = 'delivered' THEN
    PERFORM update_order_status(v_delivery.order_id, 'delivered', NULL, 'driver', NULL, TRUE);

    -- Chỉ trả tài xế về 'online' nếu KHÔNG CÒN đơn nào khác đang hoạt động (ghép đơn, xem
    -- hofa-db/107_order_batching.sql) — nếu còn, cứ để nguyên status hiện tại (đang 'busy' vì
    -- đơn kia), tự trả về 'online' khi đơn CUỐI CÙNG hoàn tất.
    SELECT EXISTS(
      SELECT 1 FROM deliveries
       WHERE driver_id = v_delivery.driver_id AND id <> p_delivery_id
         AND status NOT IN ('delivered', 'failed', 'returned')
    ) INTO v_has_other_active;
    IF NOT v_has_other_active THEN
      UPDATE drivers SET status = 'online' WHERE id = v_delivery.driver_id;
    END IF;
    UPDATE drivers SET total_deliveries = total_deliveries + 1 WHERE id = v_delivery.driver_id;

    -- Đơn mua hộ: hoàn tiền tài xế đã ứng mua hàng NGAY LÚC GIAO XONG — === MỚI === hoàn đúng
    -- TIỀN HÀNG THẬT (subtotal đã trừ phần % phí mua hộ, giờ subtotal đã gồm cả % đó — xem
    -- hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql), KHÔNG hoàn nguyên subtotal
    -- như trước nữa (sẽ hoàn dư đúng bằng phần % mà tài xế không hề bỏ tiền ra mua).
    IF v_merchant_type = 'buy_on_behalf' AND v_delivery.reimbursed_at IS NULL THEN
      INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, delivery_id)
      VALUES (
        v_delivery.driver_id, 'earning', 'buy_on_behalf_reimbursement',
        COALESCE(v_order_subtotal, 0) - COALESCE(v_order_buy_on_behalf_fee, 0), p_delivery_id
      );
      UPDATE deliveries SET reimbursed_at = now() WHERE id = p_delivery_id;
    END IF;

    IF v_delivery.earning_credited_at IS NULL THEN
      SELECT payment_method, total_amount
        INTO v_order_payment_method, v_order_total
        FROM orders WHERE id = v_delivery.order_id;
      SELECT driver_fee_commission_rate, vat_rate, pit_rate, buy_on_behalf_fee_share_rate
        INTO v_commission_rate, v_vat_rate, v_pit_rate, v_fee_share_rate
        FROM driver_finance_settings ORDER BY updated_at DESC LIMIT 1;
      v_commission_rate := COALESCE(v_commission_rate, 0);
      v_vat_rate := COALESCE(v_vat_rate, 0);
      v_pit_rate := COALESCE(v_pit_rate, 0);
      v_fee_share_rate := COALESCE(v_fee_share_rate, 0);
      v_commission_amount := ROUND(v_delivery.driver_fee * v_commission_rate / 100.0);
      v_vat_amount := ROUND(v_delivery.driver_fee * v_vat_rate / 100.0);
      v_pit_amount := ROUND(v_delivery.driver_fee * v_pit_rate / 100.0);
      v_driver_fee_net := v_delivery.driver_fee - v_commission_amount - v_vat_amount - v_pit_amount;

      -- % phí mua hộ chia cho tài xế — cộng thẳng Ví thu nhập, không trừ hoa hồng/thuế, tách
      -- biệt khỏi driver_payout (xem hofa-db/79_driver_buy_on_behalf_fee_share.sql).
      v_fee_share_amount := 0;
      IF v_merchant_type = 'buy_on_behalf' THEN
        v_fee_share_amount := ROUND(COALESCE(v_order_buy_on_behalf_fee, 0) * v_fee_share_rate / 100.0);
      END IF;
      IF v_fee_share_amount > 0 THEN
        INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, delivery_id)
        VALUES (v_delivery.driver_id, 'earning', 'buy_on_behalf_fee_share', v_fee_share_amount, p_delivery_id);
      END IF;

      INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, order_id)
      VALUES (v_delivery.driver_id, 'cod', 'order_deducted', -(v_order_total - v_driver_fee_net), v_delivery.order_id);

      IF v_order_payment_method <> 'cod' THEN
        INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, delivery_id)
        VALUES (v_delivery.driver_id, 'earning', 'order_payment_received', v_order_total, p_delivery_id);
      END IF;

      UPDATE deliveries SET
        cod_credited_at = now(), earning_credited_at = now(),
        commission_amount = v_commission_amount, vat_amount = v_vat_amount,
        pit_amount = v_pit_amount, driver_payout = v_driver_fee_net,
        buy_on_behalf_fee_share_amount = v_fee_share_amount
      WHERE id = p_delivery_id;
    END IF;
  ELSIF p_new_status = 'failed' THEN
    -- Cùng logic chỉ-trả-về-online-nếu-hết-đơn-khác như nhánh 'delivered' ở trên.
    SELECT EXISTS(
      SELECT 1 FROM deliveries
       WHERE driver_id = v_delivery.driver_id AND id <> p_delivery_id
         AND status NOT IN ('delivered', 'failed', 'returned')
    ) INTO v_has_other_active;
    IF NOT v_has_other_active THEN
      UPDATE drivers SET status = 'online' WHERE id = v_delivery.driver_id;
    END IF;
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION update_delivery_status(UUID, delivery_status, VARCHAR, VARCHAR, JSONB, VARCHAR, TEXT) IS
  'Đổi trạng thái chuyến giao. accepted: ĐẨY orders.status sang assigned (lần DUY NHẤT đơn được
   coi là "có tài xế" chính thức). picked_up: kiểm OTP (trừ đơn mua hộ dùng ảnh thay), trừ kho
   thật (BỎ QUA cho đơn mua hộ). delivered/failed: chỉ trả tài xế về online nếu KHÔNG CÒN đơn nào
   khác đang hoạt động (ghép đơn, xem hofa-db/107_order_batching.sql). delivered: hoàn tiền ứng
   mua hộ ĐÚNG GIÁ GỐC (trừ phần % phí mua hộ đã gộp vào subtotal, xem
   hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql) + cộng/trừ ví tài xế + lưu
   breakdown hoa hồng/thuế GTGT/TNCN + % phí mua hộ được chia. Đồng bộ orders.status cho cả
   accepted/picked_up/delivering/delivered.';

COMMIT;

-- ---------------------------------------------------------------------------
-- 5) Diagnostic — liệt kê cửa hàng đang có bậc phí "Số tiền cố định" (fee_type='fixed'), TẠM
--    NGỪNG được tính từ migration này. Chạy SAU COMMIT, không tự chặn gì — chỉ để admin biết
--    ngay để cân nhắc báo trước cho các cửa hàng đó nếu cần.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_row RECORD;
  v_found BOOLEAN := false;
BEGIN
  FOR v_row IN
    SELECT m.name, COUNT(*) AS fixed_tier_count
      FROM merchant_fee_tiers t
      JOIN merchants m ON m.id = t.merchant_id
     WHERE t.fee_type = 'fixed'
     GROUP BY m.name
  LOOP
    v_found := true;
    RAISE NOTICE 'Cửa hàng "%": có % bậc phí kiểu "Số tiền cố định" — tạm ngừng áp dụng từ migration 108 (chỉ còn tính phí cho bậc phần trăm).', v_row.name, v_row.fixed_tier_count;
  END LOOP;
  IF NOT v_found THEN
    RAISE NOTICE 'Không có cửa hàng nào đang dùng bậc phí "Số tiền cố định" — an toàn, không cửa hàng nào bị ảnh hưởng.';
  END IF;
END $$;
