-- ============================================================================
-- MIGRATION 79 — Tài xế nhận thêm % PHÍ MUA HỘ (orders.buy_on_behalf_fee — phí dịch vụ mua hộ
-- khách trả thêm, KHÁC subtotal đã hoàn ứng ở bước lấy hàng qua buy_on_behalf_reimbursement).
-- Tỷ lệ % là 1 dòng cấu hình DUY NHẤT áp dụng CHUNG cho mọi tài xế (driver_finance_settings,
-- giống driver_fee_commission_rate/vat_rate/pit_rate) — khác bậc phí mua hộ (merchant_fee_tiers)
-- vốn cấu hình RIÊNG theo từng cửa hàng, không đụng gì tới bảng đó.
--
-- Cộng thẳng vào Ví thu nhập lúc đơn giao xong (delivered), KHÔNG trừ hoa hồng/thuế — tách biệt
-- hẳn khỏi driver_payout (tiền công chuyến giao) để hiển thị rõ 2 khoản riêng cho tài xế.
-- ============================================================================

ALTER TABLE driver_finance_settings
  ADD COLUMN buy_on_behalf_fee_share_rate NUMERIC(5,2) NOT NULL DEFAULT 0
    CHECK (buy_on_behalf_fee_share_rate BETWEEN 0 AND 100);
COMMENT ON COLUMN driver_finance_settings.buy_on_behalf_fee_share_rate IS
  '% phí mua hộ (orders.buy_on_behalf_fee) tài xế được chia — áp dụng chung mọi tài xế, admin cấu hình. Bậc TÍNH phí mua hộ vẫn theo từng cửa hàng (merchant_fee_tiers), tỷ lệ chia này chỉ quyết định tài xế lấy bao nhiêu % của số đã tính đó.';

ALTER TABLE deliveries ADD COLUMN buy_on_behalf_fee_share_amount INTEGER NOT NULL DEFAULT 0;
COMMENT ON COLUMN deliveries.buy_on_behalf_fee_share_amount IS
  'Số tiền tài xế nhận từ phí mua hộ của đơn này (buy_on_behalf_fee_share_rate % của orders.buy_on_behalf_fee), chốt lúc giao xong — 0 nếu không phải đơn mua hộ hoặc cửa hàng chưa cấu hình phí.';

ALTER TABLE driver_wallet_transactions DROP CONSTRAINT driver_wallet_transactions_entry_type_check;
ALTER TABLE driver_wallet_transactions ADD CONSTRAINT driver_wallet_transactions_entry_type_check
  CHECK (entry_type IN (
    'cod_collected', 'cod_settled',
    'earning_released', 'buy_on_behalf_reimbursement', 'buy_on_behalf_fee_share',
    'withdrawal', 'withdrawal_rejected', 'admin_adjustment',
    'deposit',
    'order_deducted', 'order_payment_received',
    'earning_transfer_out', 'earning_transfer_in'
  ));
COMMENT ON COLUMN driver_wallet_transactions.entry_type IS
  'cod_collected/cod_settled/earning_released — KHÔNG còn insert mới (giữ lại cho dữ liệu lịch sử), xem hofa-db/69_driver_wallet_vi_tren.sql. order_deducted = trừ Ví trên lúc giao đơn (mọi phương thức). order_payment_received = cộng Ví thu nhập nguyên total_amount cho đơn chuyển khoản (KHÔNG áp dụng cho COD). earning_transfer_out/in = chuyển nội bộ 1 chiều Ví thu nhập → Ví trên. buy_on_behalf_fee_share = % phí mua hộ tài xế được chia, cộng Ví thu nhập lúc giao xong (hofa-db/79_driver_buy_on_behalf_fee_share.sql).';

-- Thân hàm giữ nguyên y hệt hofa-db/77_buy_on_behalf_unlimited_stock.sql, chỉ thêm biến +
-- khối tính/cộng buy_on_behalf_fee_share_amount trong nhánh 'delivered', và thêm cột này vào
-- UPDATE deliveries cuối cùng.
CREATE OR REPLACE FUNCTION update_delivery_status(
  p_delivery_id UUID,
  p_new_status  delivery_status,
  p_otp         VARCHAR DEFAULT NULL,       -- bắt buộc khi picked_up (trừ đơn mua hộ) hoặc delivered VÀ đơn vượt ngưỡng otp_settings
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

  -- Lấy hàng xong: trừ tồn kho thật (on_hand) và bỏ phần đã giữ (reserved) — cửa hàng mua hộ
  -- không có tồn kho thật để trừ (xem hofa-db/77_buy_on_behalf_unlimited_stock.sql).
  IF p_new_status = 'picked_up' THEN
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

    IF v_merchant_type = 'buy_on_behalf' AND v_delivery.reimbursed_at IS NULL THEN
      INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, delivery_id)
      VALUES (v_delivery.driver_id, 'earning', 'buy_on_behalf_reimbursement', COALESCE(v_order_subtotal, 0), p_delivery_id);
      UPDATE deliveries SET reimbursed_at = now() WHERE id = p_delivery_id;
    END IF;
  ELSIF p_new_status = 'delivering' THEN
    PERFORM update_order_status(v_delivery.order_id, 'delivering', NULL, 'driver', NULL, TRUE);
  ELSIF p_new_status = 'delivered' THEN
    PERFORM update_order_status(v_delivery.order_id, 'delivered', NULL, 'driver', NULL, TRUE);
    UPDATE drivers SET status = 'online', total_deliveries = total_deliveries + 1
     WHERE id = v_delivery.driver_id;

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
COMMENT ON FUNCTION update_delivery_status IS
  'Đổi trạng thái chuyến giao, kiểm OTP CHỈ khi đơn vượt ngưỡng otp_settings (trừ picked_up của đơn mua hộ — luôn dùng ảnh thay OTP), đồng bộ trạng thái đơn, trừ kho thật lúc lấy hàng (BỎ QUA cho đơn mua hộ — tồn kho vô hạn), cộng/trừ ví tài xế + lưu breakdown hoa hồng/thuế GTGT/TNCN + % phí mua hộ được chia lúc giao xong (hofa-db/79_driver_buy_on_behalf_fee_share.sql).';
