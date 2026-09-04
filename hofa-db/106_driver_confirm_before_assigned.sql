-- ============================================================================
-- MIGRATION 106 — orders.status chỉ chuyển sang 'assigned' khi TÀI XẾ THẬT SỰ XÁC NHẬN NHẬN
-- ĐƠN (deliveries.status → 'accepted'), không phải ngay lúc hệ thống MỜI tài xế (trước đây
-- assign_driver() đẩy orders.status → 'assigned' ngay lúc tạo lời mời — sai, vì lúc đó tài xế
-- còn chưa biết/chưa phản hồi gì cả). Hệ quả của lỗi cũ:
--   1. Khách/cửa hàng thấy "Đã gán tài xế" dù chưa ai xác nhận — gây hiểu lầm là đã chắc chắn.
--   2. Tài xế từ chối → orders.status vẫn kẹt ở 'assigned' (assign_driver chỉ đổi 1 LẦN DUY
--      NHẤT rồi để nguyên vĩnh viễn theo thiết kế cũ) — nếu lần tìm lại (reassignAfterDecline)
--      cũng không ra ai, đơn trông như "đã có tài xế" nhưng thực ra không có ai cả, dễ bị hiểu
--      nhầm là kẹt.
--
-- Sửa: assign_driver() (chạy lúc MỜI tài xế) bỏ hẳn việc đổi orders.status. update_delivery_
-- status() (chạy lúc tài xế xác nhận) đảm nhận việc đẩy orders.status → 'assigned', CHỈ khi
-- p_new_status = 'accepted'. Nhờ vậy 'ready_for_pickup' (hoặc 'confirmed'/'preparing' nếu tìm
-- sớm) giờ đúng nghĩa "đang tìm/đang chờ tài xế xác nhận", còn 'assigned' đúng nghĩa "đã có tài
-- xế xác nhận, đang trên đường tới lấy" — khớp nhãn hiển thị mới ở cả 3 app (xem
-- orderStatusLabels trong lib/models/order.dart từng app).
--
-- Giữ NGUYÊN chữ ký tham số của cả 2 hàm (không thêm/bớt tham số) — CREATE OR REPLACE chỉ thay
-- thế đúng khi khớp chữ ký, đổi chữ ký sẽ tạo overload thứ 2 gây lỗi "function name is not
-- unique" (đã gặp thật ở migration 105, xem hofa-db/105_early_driver_search.sql).
-- ============================================================================

-- assign_driver: bỏ hẳn khối PERFORM update_order_status(...) — mời tài xế không còn đổi
-- orders.status nữa, dù p_defer_order_status truyền gì. Tham số p_defer_order_status GIỮ LẠI
-- trong chữ ký (không dùng tới nữa) chỉ để tránh tạo overload mới — mọi lời gọi hiện tại vẫn
-- chạy được bình thường, chỉ là tham số này giờ vô nghĩa.
CREATE OR REPLACE FUNCTION assign_driver(
  p_order_id            UUID,
  p_driver_id           UUID,
  p_distance_km         NUMERIC DEFAULT NULL,
  p_eta_minutes         INTEGER DEFAULT NULL,
  p_driver_fee          INTEGER DEFAULT 0,
  p_pickup_eta_minutes  INTEGER DEFAULT NULL,
  p_defer_order_status  BOOLEAN DEFAULT FALSE
) RETURNS deliveries AS $$
DECLARE
  v_delivery deliveries;
  v_driver_user_id UUID;
  v_is_backup BOOLEAN;
  v_driver_status driver_status;
BEGIN
  SELECT user_id, is_backup_driver, status INTO v_driver_user_id, v_is_backup, v_driver_status
    FROM drivers WHERE id = p_driver_id;
  IF v_driver_user_id IS NULL THEN
    RAISE EXCEPTION 'Tài xế không tồn tại' USING ERRCODE = 'check_violation';
  END IF;
  -- Tài xế THƯỜNG vẫn phải đang online mới gán được; tài xế DỰ PHÒNG bỏ qua hẳn điều kiện này.
  IF NOT v_is_backup AND v_driver_status <> 'online' THEN
    RAISE EXCEPTION 'Tài xế không sẵn sàng nhận đơn' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO deliveries (order_id, driver_id, status, distance_km, eta_minutes, driver_fee,
                          pickup_eta_minutes, assigned_at, pickup_otp, delivery_otp)
  VALUES (p_order_id, p_driver_id, 'assigned', p_distance_km, p_eta_minutes, p_driver_fee,
          p_pickup_eta_minutes, now(), gen_otp(), gen_otp())
  ON CONFLICT (order_id) DO UPDATE SET
    driver_id = p_driver_id, status = 'assigned', distance_km = p_distance_km,
    eta_minutes = p_eta_minutes, driver_fee = p_driver_fee,
    pickup_eta_minutes = p_pickup_eta_minutes, assigned_at = now()
  RETURNING * INTO v_delivery;

  IF NOT v_is_backup THEN
    UPDATE drivers SET status = 'busy' WHERE id = p_driver_id;
  END IF;

  -- KHÔNG còn PERFORM update_order_status(...) ở đây — chỉ MỜI tài xế, orders.status giữ
  -- nguyên cho tới khi tài xế thật sự bấm nhận (xem update_delivery_status bên dưới).

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION assign_driver(UUID, UUID, NUMERIC, INTEGER, INTEGER, INTEGER, BOOLEAN) IS
  'Mời tài xế cho đơn (tạo/cập nhật dòng deliveries, status luôn là ''assigned'' = đang chờ tài
   xế phản hồi) — KHÔNG đổi orders.status, xem update_delivery_status. Tài xế thường phải đang
   online mới gán được; tài xế dự phòng (is_backup_driver=true) được gán BẤT KỂ trạng thái nào
   và không bị chuyển sang busy. p_pickup_eta_minutes = ETA tới cửa hàng. p_defer_order_status
   không còn tác dụng, giữ lại trong chữ ký để không tạo overload mới. Xem
   hofa-db/106_driver_confirm_before_assigned.sql.';

-- update_delivery_status: thêm nhánh p_new_status = 'accepted' — CHỈ lúc này mới đẩy
-- orders.status sang 'assigned' (dùng update_order_status với p_force=TRUE, giống cách 3 nhánh
-- picked_up/delivering/delivered đã làm — đơn có thể đang ở 'ready_for_pickup' (tìm bình
-- thường) hoặc 'confirmed'/'preparing' (tìm sớm), p_force bỏ qua state machine để luôn chuyển
-- được thẳng sang 'assigned' bất kể đang ở đâu trong 2 nhánh đó).
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
  v_otp_min_amount INTEGER;
  v_order_payment_method payment_method;
  v_order_total INTEGER;
  v_order_buy_on_behalf_fee INTEGER;
  v_commission_rate NUMERIC;
  v_vat_rate NUMERIC;
  v_pit_rate NUMERIC;
  v_fee_share_rate NUMERIC;
  v_commission_amount INTEGER;
  v_vat_amount INTEGER;
  v_pit_amount INTEGER;
  v_fee_share_amount INTEGER;
  v_driver_fee_net INTEGER;
BEGIN
  SELECT * INTO v_delivery FROM deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy chuyến giao hàng' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT m.merchant_type, o.subtotal, o.total_amount
    INTO v_merchant_type, v_order_subtotal, v_order_total_amount
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
    UPDATE drivers SET status = 'online', total_deliveries = total_deliveries + 1
     WHERE id = v_delivery.driver_id;

    -- Đơn mua hộ: hoàn tiền tài xế đã ứng mua hàng NGAY LÚC GIAO XONG — khớp đúng nội dung
    -- thông báo hiện trên app (trước migration này hoàn ngay lúc 'picked_up', xem
    -- hofa-db/79_driver_buy_on_behalf_fee_share.sql).
    IF v_merchant_type = 'buy_on_behalf' AND v_delivery.reimbursed_at IS NULL THEN
      INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, delivery_id)
      VALUES (v_delivery.driver_id, 'earning', 'buy_on_behalf_reimbursement', COALESCE(v_order_subtotal, 0), p_delivery_id);
      UPDATE deliveries SET reimbursed_at = now() WHERE id = p_delivery_id;
    END IF;

    IF v_delivery.earning_credited_at IS NULL THEN
      SELECT payment_method, total_amount, buy_on_behalf_fee
        INTO v_order_payment_method, v_order_total, v_order_buy_on_behalf_fee
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
    UPDATE drivers SET status = 'online' WHERE id = v_delivery.driver_id;
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION update_delivery_status(UUID, delivery_status, VARCHAR, VARCHAR, JSONB, VARCHAR, TEXT) IS
  'Đổi trạng thái chuyến giao. accepted: ĐẨY orders.status sang assigned (lần DUY NHẤT đơn được
   coi là "có tài xế" chính thức, xem hofa-db/106_driver_confirm_before_assigned.sql). picked_up:
   kiểm OTP (trừ đơn mua hộ dùng ảnh thay), trừ kho thật (BỎ QUA cho đơn mua hộ). delivered: hoàn
   tiền ứng mua hộ + cộng/trừ ví tài xế + lưu breakdown hoa hồng/thuế GTGT/TNCN + % phí mua hộ
   được chia. Đồng bộ orders.status cho cả accepted/picked_up/delivering/delivered.';
