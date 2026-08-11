-- ============================================================================
-- MIGRATION 69 — Ví COD tài xế đổi vai trò thành "Ví trên": ví VỐN phải nạp trước mới chạy
-- được đơn, bị TRỪ lúc giao đơn (mọi phương thức thanh toán) thay vì được CỘNG tiền COD như
-- trước. Ví thu nhập giờ chỉ còn là tiền thật rút được về ngân hàng. Thay hẳn vai trò "ký quỹ
-- tối thiểu để nhận đơn" từ earning_balance (hofa-db/63) sang cod_balance (Ví trên).
--
-- Định danh nội bộ `wallet='cod'` KHÔNG đổi tên trong DB/API — chỉ đổi nhãn hiển thị "Ví trên"
-- ở Flutter, tránh phải sửa lại mọi chỗ tham chiếu wallet='cod' chỉ để đổi tên.
--
-- Công thức mới lúc đơn giao xong (nhánh 'delivered' trong update_delivery_status):
--   - Ví trên: LUÔN trừ (total_amount - phần tài xế thực nhận), mọi phương thức thanh toán.
--   - Ví thu nhập: COD thì KHÔNG cộng gì (tài xế đã cầm tiền mặt thật trong tay); chuyển khoản/
--     đã xác nhận thanh toán online thì cộng NGUYÊN total_amount (không chỉ phần tài xế) — đã
--     xác nhận lại với người dùng kèm ví dụ số và cảnh báo rủi ro (tài xế rút được cả phần
--     không phải của mình về ngân hàng thật), người dùng chọn giữ nguyên đúng yêu cầu.
--
-- Bỏ hẳn luồng "Nộp COD" (driver_cod_settlements) và cod_debt_limit (driver_finance_settings)
-- — ý nghĩa CŨ của ví cod (nợ, càng nhiều càng xấu) trái ngược ý nghĩa MỚI (vốn, càng nhiều càng
-- tốt), không thể chạy song song. Bảng/route liên quan GIỮ NGUYÊN trong DB, chỉ ngừng gọi từ UI.
--
-- Ví trên là ví MỘT CHIỀU VÀO — không rút/chuyển đi đâu được. Tiền vào Ví trên qua (a) "Nạp
-- tiền" ngân hàng có admin duyệt (driver_wallet_deposits, đổi ví đích ở server/src/routes/
-- drivers.js), hoặc (b) chuyển nội bộ MỘT CHIỀU từ Ví thu nhập (RPC deposit_earning_to_vi_tren
-- bên dưới, không cần duyệt).
-- ============================================================================

BEGIN;

ALTER TABLE driver_wallet_transactions DROP CONSTRAINT driver_wallet_transactions_entry_type_check;
ALTER TABLE driver_wallet_transactions ADD CONSTRAINT driver_wallet_transactions_entry_type_check
  CHECK (entry_type IN (
    'cod_collected', 'cod_settled',
    'earning_released', 'buy_on_behalf_reimbursement',
    'withdrawal', 'withdrawal_rejected', 'admin_adjustment',
    'deposit',
    'order_deducted', 'order_payment_received',
    'earning_transfer_out', 'earning_transfer_in'
  ));
COMMENT ON COLUMN driver_wallet_transactions.entry_type IS
  'cod_collected/cod_settled/earning_released — KHÔNG còn insert mới (giữ lại cho dữ liệu lịch sử), xem hofa-db/69_driver_wallet_vi_tren.sql. order_deducted = trừ Ví trên lúc giao đơn (mọi phương thức). order_payment_received = cộng Ví thu nhập nguyên total_amount cho đơn chuyển khoản (KHÔNG áp dụng cho COD). earning_transfer_out/in = chuyển nội bộ 1 chiều Ví thu nhập → Ví trên.';

-- update_delivery_status(): chữ ký giữ nguyên, thân hàm giữ nguyên phần còn lại y hệt
-- hofa-db/62_driver_wallet_ledger.sql, chỉ đổi khối "Cộng ví" ở nhánh 'delivered'.
CREATE OR REPLACE FUNCTION update_delivery_status(
  p_delivery_id UUID,
  p_new_status  delivery_status,
  p_otp         VARCHAR DEFAULT NULL,       -- bắt buộc khi picked_up (trừ đơn mua hộ) hoặc delivered
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
  v_order_payment_method payment_method;
  v_order_total INTEGER;
  v_commission_rate NUMERIC;
  v_driver_fee_net INTEGER;
BEGIN
  SELECT * INTO v_delivery FROM deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy chuyến giao hàng' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT m.merchant_type, o.subtotal INTO v_merchant_type, v_order_subtotal
    FROM orders o JOIN merchants m ON m.id = o.merchant_id
   WHERE o.id = v_delivery.order_id;

  -- Đơn mua hộ: tài xế tự đi mua, không có nhân viên cửa hàng nào đọc OTP lấy hàng cho tài xế
  -- — bỏ OTP ở bước này, bắt buộc ít nhất 1 ảnh hoá đơn/hàng đã mua làm bằng chứng thay thế.
  -- Đơn thường giữ nguyên yêu cầu OTP như trước.
  IF p_new_status = 'picked_up' THEN
    IF v_merchant_type = 'buy_on_behalf' THEN
      IF p_proof_photo_urls IS NULL OR jsonb_array_length(p_proof_photo_urls) = 0 THEN
        RAISE EXCEPTION 'Cần ít nhất 1 ảnh hoá đơn/hàng đã mua' USING ERRCODE = 'check_violation';
      END IF;
    ELSIF p_otp IS NULL OR p_otp <> v_delivery.pickup_otp THEN
      RAISE EXCEPTION 'Mã OTP lấy hàng không đúng' USING ERRCODE = 'check_violation';
    END IF;
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

    -- Mua hộ: hoàn ngay tiền hàng tài xế vừa ứng ra mua — tách biệt phí giao hàng (vẫn cộng
    -- lúc giao xong như bình thường ở nhánh 'delivered' bên dưới). Chặn cộng 2 lần bằng
    -- reimbursed_at (v_delivery ở đây là bản TRƯỚC UPDATE reimbursed_at nên vẫn đọc đúng). Tiền
    -- hoàn là VỐN tài xế tự bỏ ra, không phải thu nhập/COD nợ HOFA nên ghi vào ví thu nhập
    -- (rút được ngay), khác entry_type với earning_released để phân biệt lúc xem lịch sử.
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

    -- Cộng/trừ ví — Ví trên (wallet='cod') LUÔN bị trừ (total_amount - phần tài xế thực nhận),
    -- mọi phương thức thanh toán. Ví thu nhập: COD không cộng gì (tài xế cầm tiền mặt thật rồi);
    -- chuyển khoản/đã xác nhận thanh toán online thì cộng NGUYÊN total_amount. Guard
    -- earning_credited_at chống chạy trùng (dùng chung cho cả 2 khối, như trước).
    IF v_delivery.earning_credited_at IS NULL THEN
      SELECT payment_method, total_amount INTO v_order_payment_method, v_order_total
        FROM orders WHERE id = v_delivery.order_id;
      SELECT driver_fee_commission_rate INTO v_commission_rate
        FROM driver_finance_settings ORDER BY updated_at DESC LIMIT 1;
      v_commission_rate := COALESCE(v_commission_rate, 0);
      v_driver_fee_net := v_delivery.driver_fee - ROUND(v_delivery.driver_fee * v_commission_rate / 100.0);

      INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, order_id)
      VALUES (v_delivery.driver_id, 'cod', 'order_deducted', -(v_order_total - v_driver_fee_net), v_delivery.order_id);

      IF v_order_payment_method <> 'cod' THEN
        INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, delivery_id)
        VALUES (v_delivery.driver_id, 'earning', 'order_payment_received', v_order_total, p_delivery_id);
      END IF;

      UPDATE deliveries SET cod_credited_at = now(), earning_credited_at = now() WHERE id = p_delivery_id;
    END IF;
  ELSIF p_new_status = 'failed' THEN
    UPDATE drivers SET status = 'online' WHERE id = v_delivery.driver_id;
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION update_delivery_status IS
  'Đổi trạng thái chuyến giao, kiểm OTP (trừ picked_up của đơn mua hộ — dùng ảnh thay OTP), đồng bộ trạng thái đơn, trừ kho thật lúc lấy hàng, cộng/trừ ví tài xế lúc giao xong (Ví trên luôn trừ, Ví thu nhập chỉ cộng cho đơn không phải COD) và lúc mua xong nếu là đơn mua hộ — xem hofa-db/69_driver_wallet_vi_tren.sql.';

-- Rút tiền: chữ ký + thân hàm y hệt hofa-db/62_driver_wallet_ledger.sql, chỉ BỎ khối kiểm tra
-- cod_balance > cod_debt_limit — hạn mức COD không còn ý nghĩa (Ví trên giờ là vốn, không phải
-- nợ). Rút tiền thật vẫn CHỈ đụng ví thu nhập, không đổi.
CREATE OR REPLACE FUNCTION request_driver_withdrawal(p_driver_id UUID, p_amount INTEGER)
RETURNS driver_wallet_withdrawals AS $$
DECLARE
  v_earning_balance INTEGER;
  v_min_balance INTEGER;
  v_withdrawal driver_wallet_withdrawals;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Số tiền rút không hợp lệ' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM 1 FROM drivers WHERE id = p_driver_id FOR UPDATE;

  SELECT COALESCE(SUM(amount) FILTER (WHERE wallet = 'earning'), 0)
    INTO v_earning_balance
    FROM driver_wallet_transactions WHERE driver_id = p_driver_id;

  SELECT min_withdrawal_balance INTO v_min_balance FROM bank_account_settings ORDER BY updated_at DESC LIMIT 1;
  v_min_balance := COALESCE(v_min_balance, 0);

  IF v_earning_balance - p_amount < v_min_balance THEN
    RAISE EXCEPTION 'Số dư ví thu nhập không đủ để rút số tiền này' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO driver_wallet_withdrawals (driver_id, amount) VALUES (p_driver_id, p_amount)
    RETURNING * INTO v_withdrawal;
  INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, withdrawal_id)
    VALUES (p_driver_id, 'earning', 'withdrawal', -p_amount, v_withdrawal.id);

  RETURN v_withdrawal;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION request_driver_withdrawal IS
  'Kiểm earning_balance đủ, rồi tạo yêu cầu rút + dòng sổ cái entry_type=withdrawal trong 1 transaction — xem POST /drivers/me/wallet/withdrawals (server). Không còn kiểm cod_balance (xem hofa-db/69_driver_wallet_vi_tren.sql).';

-- Chuyển nội bộ MỘT CHIỀU DUY NHẤT: Ví thu nhập → Ví trên, không cần admin duyệt (khác hẳn nạp/
-- rút tiền thật qua ngân hàng) — atomic, khoá drivers row trước khi kiểm số dư.
CREATE OR REPLACE FUNCTION deposit_earning_to_vi_tren(p_driver_id UUID, p_amount INTEGER)
RETURNS void AS $$
DECLARE
  v_earning_balance INTEGER;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Số tiền không hợp lệ' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM 1 FROM drivers WHERE id = p_driver_id FOR UPDATE;

  SELECT COALESCE(SUM(amount) FILTER (WHERE wallet = 'earning'), 0)
    INTO v_earning_balance
    FROM driver_wallet_transactions WHERE driver_id = p_driver_id;

  IF p_amount > v_earning_balance THEN
    RAISE EXCEPTION 'Số dư ví thu nhập không đủ để chuyển' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount)
  VALUES (p_driver_id, 'earning', 'earning_transfer_out', -p_amount);
  INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount)
  VALUES (p_driver_id, 'cod', 'earning_transfer_in', p_amount);
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION deposit_earning_to_vi_tren IS
  'Chuyển nội bộ 1 chiều Ví thu nhập → Ví trên, tự động ngay lập tức không cần admin duyệt — xem POST /drivers/me/wallet/transfer-to-vi-tren (server).';

COMMIT;
