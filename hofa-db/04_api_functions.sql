-- ============================================================================
-- HOFA PLATFORM — API FUNCTIONS (RPC cho lớp API viết bằng Google Apps Script)
-- PostgreSQL 14+ | Version 1.0 | 2026-07-30
--
-- Vì sao cần file này:
-- GAS gọi Supabase qua HTTP (UrlFetchApp), mỗi lần gọi là một request rời rạc,
-- KHÔNG tự động gộp thành 1 transaction. Những nghiệp vụ đụng nhiều bảng cùng
-- lúc (tạo đơn = orders + order_items + giữ tồn kho, đổi trạng thái đơn kèm
-- tác động tồn kho...) phải nằm trong 1 hàm Postgres để đảm bảo hoặc tất cả
-- cùng thành công, hoặc tất cả cùng rollback.
--
-- Các hàm ở đây được PostgREST tự động lộ ra thành endpoint:
--   POST /rest/v1/rpc/<tên_hàm>
-- GAS chỉ việc gọi RPC này thay vì tự ghép nhiều lệnh INSERT/UPDATE.
--
-- Toàn bộ hàm SECURITY DEFINER: chạy bằng quyền chủ sở hữu (bỏ qua RLS),
-- vì lớp kiểm tra quyền (ai được làm gì) đã nằm ở GAS (xác minh JWT + role).
-- KHÔNG gọi các hàm này trực tiếp bằng anon key từ client — chỉ GAS
-- (dùng service_role key) mới được gọi.
-- ============================================================================

BEGIN;

-- ============================================================================
-- PHẦN 0: TIỆN ÍCH DÙNG CHUNG
-- ============================================================================

CREATE OR REPLACE FUNCTION gen_otp() RETURNS VARCHAR AS $$
BEGIN
  RETURN lpad((floor(random() * 1000000))::INT::TEXT, 6, '0');
END;
$$ LANGUAGE plpgsql;

-- Giữ chỗ tồn kho khi tạo đơn (KHÔNG trừ on_hand, chỉ tăng reserved).
-- Trừ on_hand thật sự chỉ xảy ra lúc tài xế lấy hàng (xem update_delivery_status).
CREATE OR REPLACE FUNCTION reserve_inventory(
  p_branch_id UUID, p_variant_id UUID, p_quantity INTEGER
) RETURNS VOID AS $$
DECLARE
  v_available INTEGER;
BEGIN
  INSERT INTO inventory (branch_id, variant_id, quantity_on_hand)
  VALUES (p_branch_id, p_variant_id, 0)
  ON CONFLICT (branch_id, variant_id) DO NOTHING;

  SELECT (quantity_on_hand - quantity_reserved) INTO v_available
  FROM inventory WHERE branch_id = p_branch_id AND variant_id = p_variant_id
  FOR UPDATE;

  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Không đủ hàng tồn kho (còn %, cần %)', v_available, p_quantity
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE inventory SET quantity_reserved = quantity_reserved + p_quantity
  WHERE branch_id = p_branch_id AND variant_id = p_variant_id;
END;
$$ LANGUAGE plpgsql;

-- Nhả chỗ đã giữ (khi huỷ đơn trước lúc lấy hàng)
CREATE OR REPLACE FUNCTION release_inventory(
  p_branch_id UUID, p_variant_id UUID, p_quantity INTEGER
) RETURNS VOID AS $$
BEGIN
  UPDATE inventory
     SET quantity_reserved = GREATEST(quantity_reserved - p_quantity, 0)
   WHERE branch_id = p_branch_id AND variant_id = p_variant_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION reserve_inventory IS 'Giữ chỗ tồn kho lúc đặt hàng. Không trừ on_hand, chỉ tăng reserved';
COMMENT ON FUNCTION release_inventory IS 'Nhả chỗ đã giữ khi đơn bị huỷ trước khi lấy hàng';

-- Giá thật của 1 biến thể khi đặt hàng: ưu tiên bậc giá (wholesale_tiers) khớp điều kiện,
-- nếu không có bậc nào khớp thì dùng lại giá bán gốc (p_base_price = product_variants.price).
-- p_is_preorder chọn đúng LOẠI bậc được xét — 1 biến thể có thể có cả 2 loại cùng lúc
-- (xem migration 14) nên phải cách ly hẳn, không để đơn "giá sỉ" vô tình khớp trúng bậc
-- "đặt trước" hay ngược lại:
--   false -> chỉ xét bậc "giá sỉ" (min_days_per_week = 0): số lượng RIÊNG món này
--     (p_quantity) >= min_quantity, HOẶC (nếu bậc có cấu hình min_order_quantity) tổng
--     số lượng CẢ đơn (p_order_quantity, gộp mọi món) >= min_order_quantity — đạt 1
--     trong 2 là được giá bậc này, dùng đúng 1 giá (unit_price).
--   true  -> chỉ xét bậc "đặt trước" (min_days_per_week > 0): 2 điều kiện ĐỘC LẬP —
--     (1) số lượng, so theo p_order_quantity (TỔNG số lượng CẢ lần giao, gộp mọi món);
--     (2) số ngày/tuần, so p_days_count (số ngày/tuần khách đặt RIÊNG món này) với
--     min_days_per_week. Đạt điều kiện nào lấy giá tương ứng: chỉ số lượng -> unit_price,
--     chỉ số ngày -> unit_price_days, cả 2 -> unit_price_both (thường rẻ nhất).
-- Nhiều bậc cùng khớp thì ưu tiên bậc có min_quantity cao nhất, rồi tới min_days_per_week
-- cao nhất (khớp càng nhiều điều kiện càng ưu tiên).
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
      (
        (CASE WHEN t.min_days_per_week = 0 THEN p_quantity ELSE p_order_quantity END) >= t.min_quantity
          AND (t.max_quantity IS NULL
               OR (CASE WHEN t.min_days_per_week = 0 THEN p_quantity ELSE p_order_quantity END) <= t.max_quantity)
      )
      -- Bậc giá sỉ có thêm điều kiện THAY THẾ theo tổng số lượng cả đơn (xem comment cột
      -- min_order_quantity) — đạt 1 trong 2 là được giá bậc này.
      OR (t.min_days_per_week = 0 AND t.min_order_quantity IS NOT NULL AND p_order_quantity >= t.min_order_quantity)
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
  'Chốt giá thật theo bậc giá — p_is_preorder=false chỉ xét bậc giá sỉ (số lượng riêng món HOẶC tổng số lượng cả đơn nếu bậc có cấu hình min_order_quantity), true chỉ xét bậc đặt trước (so tổng số lượng cả lần giao VÀ số ngày/tuần riêng món) — không có bậc nào khớp thì trả về giá bán gốc';

-- ============================================================================
-- PHẦN 1: TẠO ĐƠN HÀNG (SDD 7.5)
-- p_items: [{"variant_id":"uuid","quantity":2,"note":"không lấy đá"}, ...]
-- Giá KHÔNG lấy từ client — luôn chốt qua resolve_variant_price() (bậc giá sỉ/đặt trước
-- khớp số lượng, không khớp bậc nào thì lấy giá bán gốc product_variants.price), để khách
-- không thể sửa giá bằng cách sửa request.
-- ============================================================================

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

-- ============================================================================
-- PHẦN 2: ĐỔI TRẠNG THÁI ĐƠN HÀNG (state machine)
-- ============================================================================

CREATE OR REPLACE FUNCTION update_order_status(
  p_order_id   UUID,
  p_new_status order_status,
  p_changed_by UUID DEFAULT NULL,
  p_actor_role user_role DEFAULT NULL,
  p_note       TEXT DEFAULT NULL,
  p_force      BOOLEAN DEFAULT FALSE   -- admin ép chuyển, bỏ qua state machine
) RETURNS orders AS $$
DECLARE
  v_order orders;
  v_allowed order_status[];
  v_item RECORD;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy đơn hàng' USING ERRCODE = 'no_data_found';
  END IF;

  v_allowed := CASE v_order.status
    WHEN 'pending_payment'  THEN ARRAY['placed','cancelled']::order_status[]
    WHEN 'placed'           THEN ARRAY['confirmed','cancelled']::order_status[]
    WHEN 'confirmed'        THEN ARRAY['preparing','cancelled']::order_status[]
    WHEN 'preparing'        THEN ARRAY['ready_for_pickup','cancelled']::order_status[]
    WHEN 'ready_for_pickup' THEN ARRAY['assigned','cancelled']::order_status[]
    WHEN 'assigned'         THEN ARRAY['picked_up','cancelled']::order_status[]
    WHEN 'picked_up'        THEN ARRAY['delivering']::order_status[]
    WHEN 'delivering'       THEN ARRAY['delivered','cancelled']::order_status[]
    WHEN 'delivered'        THEN ARRAY['completed','refunded']::order_status[]
    WHEN 'completed'        THEN ARRAY['refunded']::order_status[]
    ELSE ARRAY[]::order_status[]
  END;

  IF NOT p_force AND NOT (p_new_status = ANY(v_allowed)) THEN
    RAISE EXCEPTION 'Không thể chuyển đơn từ % sang %', v_order.status, p_new_status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Huỷ đơn trước khi lấy hàng: nhả chỗ tồn kho đã giữ
  IF p_new_status = 'cancelled' AND v_order.status IN
     ('pending_payment','placed','confirmed','preparing','ready_for_pickup','assigned') THEN
    FOR v_item IN SELECT variant_id, quantity FROM order_items WHERE order_id = p_order_id LOOP
      IF v_item.variant_id IS NOT NULL THEN
        PERFORM release_inventory(v_order.branch_id, v_item.variant_id, v_item.quantity);
      END IF;
    END LOOP;

    -- Nếu đơn đã lỡ gán tài xế (status = 'assigned') rồi mới huỷ, trả tài xế về
    -- trạng thái online, không thôi tài xế bị kẹt ở 'busy' vĩnh viễn
    UPDATE drivers SET status = 'online'
     WHERE status = 'busy'
       AND id = (SELECT driver_id FROM deliveries WHERE order_id = p_order_id);
  END IF;

  UPDATE orders SET
    status = p_new_status,
    confirmed_at = CASE WHEN p_new_status = 'confirmed' THEN now() ELSE confirmed_at END,
    ready_at     = CASE WHEN p_new_status = 'ready_for_pickup' THEN now() ELSE ready_at END,
    picked_up_at = CASE WHEN p_new_status = 'picked_up' THEN now() ELSE picked_up_at END,
    delivered_at = CASE WHEN p_new_status = 'delivered' THEN now() ELSE delivered_at END,
    cancelled_at = CASE WHEN p_new_status = 'cancelled' THEN now() ELSE cancelled_at END,
    cancel_reason = CASE WHEN p_new_status = 'cancelled' THEN p_note ELSE cancel_reason END,
    cancelled_by  = CASE WHEN p_new_status = 'cancelled' THEN p_changed_by ELSE cancelled_by END
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- Trigger trg_orders_status_log đã tự thêm dòng lịch sử; bổ sung ai/ghi chú vào dòng vừa tạo
  UPDATE order_status_history SET changed_by = p_changed_by, actor_role = p_actor_role, note = p_note
   WHERE id = (
     SELECT id FROM order_status_history
      WHERE order_id = p_order_id AND to_status = p_new_status
      ORDER BY created_at DESC LIMIT 1
   );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION update_order_status IS
  'Đổi trạng thái đơn theo đúng state machine, tự nhả tồn kho khi huỷ, ghi lại ai đổi';

-- ============================================================================
-- PHẦN 3: GÁN TÀI XẾ & GIAO HÀNG (SDD 7.6, 7.10)
-- ============================================================================

CREATE OR REPLACE FUNCTION assign_driver(
  p_order_id     UUID,
  p_driver_id    UUID,
  p_distance_km  NUMERIC DEFAULT NULL,
  p_eta_minutes  INTEGER DEFAULT NULL,
  p_driver_fee   INTEGER DEFAULT 0
) RETURNS deliveries AS $$
DECLARE
  v_delivery deliveries;
  v_order_status order_status;
  v_driver_user_id UUID;
BEGIN
  -- order_status_history.changed_by trỏ tới users(id), không phải drivers(id) —
  -- phải tra ra user_id thật của tài xế trước khi ghi lịch sử đơn hàng.
  SELECT user_id INTO v_driver_user_id FROM drivers WHERE id = p_driver_id AND status = 'online';
  IF v_driver_user_id IS NULL THEN
    RAISE EXCEPTION 'Tài xế không tồn tại hoặc không sẵn sàng nhận đơn' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO deliveries (order_id, driver_id, status, distance_km, eta_minutes, driver_fee,
                          assigned_at, pickup_otp, delivery_otp)
  VALUES (p_order_id, p_driver_id, 'assigned', p_distance_km, p_eta_minutes, p_driver_fee,
          now(), gen_otp(), gen_otp())
  ON CONFLICT (order_id) DO UPDATE SET
    driver_id = p_driver_id, status = 'assigned', distance_km = p_distance_km,
    eta_minutes = p_eta_minutes, driver_fee = p_driver_fee, assigned_at = now()
  RETURNING * INTO v_delivery;

  UPDATE drivers SET status = 'busy' WHERE id = p_driver_id;

  -- Chỉ đổi order_status lần gán ĐẦU TIÊN. Khi tài xế từ chối/hết hạn và đơn
  -- được tự động gán lại cho tài xế khác (order vẫn đang ở 'assigned'), state
  -- machine của update_order_status không cho phép 'assigned' -> 'assigned'.
  SELECT status INTO v_order_status FROM orders WHERE id = p_order_id;
  IF v_order_status IS DISTINCT FROM 'assigned' THEN
    PERFORM update_order_status(p_order_id, 'assigned', v_driver_user_id, 'driver', 'Đã gán tài xế');
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION assign_driver IS 'Gán tài xế cho đơn, sinh OTP lấy hàng/giao hàng, đổi đơn sang trạng thái assigned';

CREATE OR REPLACE FUNCTION update_delivery_status(
  p_delivery_id UUID,
  p_new_status  delivery_status,
  p_otp         VARCHAR DEFAULT NULL,       -- bắt buộc khi picked_up hoặc delivered
  p_recipient_name VARCHAR DEFAULT NULL,
  p_proof_photo_urls JSONB DEFAULT NULL,
  p_signature_url VARCHAR DEFAULT NULL,
  p_failure_reason TEXT DEFAULT NULL
) RETURNS deliveries AS $$
DECLARE
  v_delivery deliveries;
  v_item RECORD;
BEGIN
  SELECT * INTO v_delivery FROM deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy chuyến giao hàng' USING ERRCODE = 'no_data_found';
  END IF;

  IF p_new_status = 'picked_up' AND (p_otp IS NULL OR p_otp <> v_delivery.pickup_otp) THEN
    RAISE EXCEPTION 'Mã OTP lấy hàng không đúng' USING ERRCODE = 'check_violation';
  END IF;
  IF p_new_status = 'delivered' AND (p_otp IS NULL OR p_otp <> v_delivery.delivery_otp) THEN
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

  -- Lấy hàng xong: trừ tồn kho thật (on_hand) và bỏ phần đã giữ (reserved)
  IF p_new_status = 'picked_up' THEN
    FOR v_item IN
      SELECT oi.variant_id, oi.quantity FROM order_items oi
       JOIN orders o ON o.id = oi.order_id WHERE o.id = (
         SELECT order_id FROM deliveries WHERE id = p_delivery_id
       )
    LOOP
      IF v_item.variant_id IS NOT NULL THEN
        -- Thứ tự bắt buộc: nhả reserved TRƯỚC, trừ on_hand SAU. Nếu làm ngược lại,
        -- khi nhiều đơn khác cũng đang giữ chỗ cùng biến thể (reserved cộng dồn cao),
        -- bước trừ on_hand có thể tạm thời làm on_hand < reserved và vi phạm
        -- CHECK inventory_reserved_lte_hand ngay giữa chừng (constraint không hoãn được).
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
    PERFORM update_order_status(v_delivery.order_id, 'picked_up', NULL, 'driver', NULL, TRUE);
  ELSIF p_new_status = 'delivering' THEN
    PERFORM update_order_status(v_delivery.order_id, 'delivering', NULL, 'driver', NULL, TRUE);
  ELSIF p_new_status = 'delivered' THEN
    PERFORM update_order_status(v_delivery.order_id, 'delivered', NULL, 'driver', NULL, TRUE);
    UPDATE drivers SET status = 'online', total_deliveries = total_deliveries + 1
     WHERE id = v_delivery.driver_id;
    -- COD: tiền vào ví tài xế, trừ lại phí giao được trả
    IF (SELECT payment_method FROM orders WHERE id = v_delivery.order_id) = 'cod' THEN
      UPDATE drivers SET wallet_balance = wallet_balance
        + (SELECT total_amount FROM orders WHERE id = v_delivery.order_id)
        - v_delivery.driver_fee
       WHERE id = v_delivery.driver_id;
    END IF;
  ELSIF p_new_status = 'failed' THEN
    UPDATE drivers SET status = 'online' WHERE id = v_delivery.driver_id;
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION update_delivery_status IS
  'Đổi trạng thái chuyến giao, kiểm OTP, đồng bộ trạng thái đơn, trừ kho thật lúc lấy hàng, cộng ví tài xế lúc giao xong';

-- ============================================================================
-- PHẦN 4: THANH TOÁN (SDD 7.7)
-- ============================================================================

CREATE OR REPLACE FUNCTION record_payment(
  p_order_id        UUID,
  p_method          payment_method,
  p_amount          INTEGER,
  p_gateway         VARCHAR DEFAULT NULL,
  p_transaction_code VARCHAR DEFAULT NULL,
  p_collected_by    UUID DEFAULT NULL,
  p_gateway_response JSONB DEFAULT NULL
) RETURNS payments AS $$
DECLARE
  v_payment payments;
  v_total_paid INTEGER;
BEGIN
  INSERT INTO payments (order_id, method, status, amount, gateway, transaction_code,
                         collected_by, gateway_response, paid_at)
  VALUES (p_order_id, p_method, 'paid', p_amount, p_gateway, p_transaction_code,
          p_collected_by, p_gateway_response, now())
  RETURNING * INTO v_payment;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid FROM payments
   WHERE order_id = p_order_id AND status = 'paid';

  UPDATE orders SET
    payment_status = (CASE WHEN v_total_paid >= total_amount THEN 'paid' ELSE 'pending' END)::payment_status
  WHERE id = p_order_id;

  IF (SELECT status FROM orders WHERE id = p_order_id) = 'pending_payment'
     AND v_total_paid >= (SELECT total_amount FROM orders WHERE id = p_order_id) THEN
    PERFORM update_order_status(p_order_id, 'placed', p_collected_by, NULL, 'Đã thanh toán');
  END IF;

  RETURN v_payment;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION record_payment IS 'Ghi nhận thanh toán, tự cập nhật payment_status của đơn và mở khoá đơn pending_payment';

CREATE OR REPLACE FUNCTION refund_payment(
  p_payment_id UUID,
  p_amount     INTEGER,
  p_note       TEXT DEFAULT NULL
) RETURNS payments AS $$
DECLARE
  v_payment payments;
BEGIN
  SELECT * INTO v_payment FROM payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy giao dịch' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_payment.refunded_amount + p_amount > v_payment.amount THEN
    RAISE EXCEPTION 'Số tiền hoàn vượt quá số đã thu' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE payments SET
    refunded_amount = refunded_amount + p_amount,
    refunded_at = now(),
    status = (CASE WHEN refunded_amount + p_amount >= amount THEN 'refunded' ELSE 'partially_refunded' END)::payment_status,
    note = COALESCE(p_note, note)
  WHERE id = p_payment_id
  RETURNING * INTO v_payment;

  UPDATE orders SET payment_status =
    (CASE WHEN v_payment.status = 'refunded' THEN 'refunded' ELSE 'partially_refunded' END)::payment_status
  WHERE id = v_payment.order_id;

  RETURN v_payment;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION refund_payment IS 'Hoàn tiền một phần hoặc toàn bộ cho một giao dịch';

COMMIT;

-- ============================================================================
-- KẾT THÚC. 8 hàm RPC dùng cho lớp API (GAS): create_order, update_order_status,
-- assign_driver, update_delivery_status, record_payment, refund_payment,
-- reserve_inventory, release_inventory, gen_otp.
-- Chạy file này SAU 01_schema.sql (và sau 02_seed nếu bạn đã chạy).
-- ============================================================================
