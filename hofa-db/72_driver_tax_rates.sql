-- ============================================================================
-- MIGRATION 72 — Thu nhập tài xế tính hoa hồng + thuế GTGT/TNCN GIỐNG cửa hàng: chốt lúc giao
-- xong (driver_payout = driver_fee - commission_amount - vat_amount - pit_amount), lưu lại 4
-- cột breakdown trên deliveries để hiển thị rõ ở app tài xế (chi tiết chuyến giao + màn Thu
-- nhập), thay vì chỉ trừ "ẩn" vào trong ví như trước (hofa-db/69_driver_wallet_vi_tren.sql).
--
-- vat_rate/pit_rate MỚI thêm vào driver_finance_settings (mặc định 0% — an toàn, giống cách
-- driver_fee_commission_rate mặc định 0 khi ra mắt, xem hofa-db/62_driver_wallet_ledger.sql),
-- admin bật lên khi cần ở web admin. Công thức TRỪ THẲNG lên driver_fee (không lồng thuế trong
-- thuế), cùng cách tính với merchants (hofa-db/33_merchant_tax_rates.sql, hofa-db/67).
--
-- Backfill: chuyến ĐÃ giao trước migration này khôi phục lại đúng commission_amount/
-- driver_payout ĐÃ THỰC SỰ áp dụng — đọc ngược từ driver_wallet_transactions.entry_type=
-- 'order_deducted' đã ghi sổ (không phải đoán). vat_amount/pit_amount giữ 0 vì trước đây chưa
-- hề có 2 khoản này.
-- ============================================================================

ALTER TABLE driver_finance_settings ADD COLUMN vat_rate NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (vat_rate >= 0 AND vat_rate <= 100);
ALTER TABLE driver_finance_settings ADD COLUMN pit_rate NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (pit_rate >= 0 AND pit_rate <= 100);
COMMENT ON COLUMN driver_finance_settings.vat_rate IS 'Thuế suất GTGT (%) trừ thẳng trên phí giao (driver_fee) — mặc định 0%, admin bật khi cần.';
COMMENT ON COLUMN driver_finance_settings.pit_rate IS 'Thuế suất TNCN (%) trừ thẳng trên phí giao (driver_fee) — mặc định 0%, admin bật khi cần.';

ALTER TABLE deliveries ADD COLUMN commission_amount INTEGER NOT NULL DEFAULT 0;
ALTER TABLE deliveries ADD COLUMN vat_amount        INTEGER NOT NULL DEFAULT 0;
ALTER TABLE deliveries ADD COLUMN pit_amount        INTEGER NOT NULL DEFAULT 0;
ALTER TABLE deliveries ADD COLUMN driver_payout     INTEGER NOT NULL DEFAULT 0;
COMMENT ON COLUMN deliveries.commission_amount IS 'Hoa hồng HOFA cắt trên driver_fee — chốt lúc giao xong theo driver_finance_settings.driver_fee_commission_rate tại thời điểm đó.';
COMMENT ON COLUMN deliveries.vat_amount IS 'Thuế GTGT ước tính trên driver_fee — chốt lúc giao xong theo driver_finance_settings.vat_rate tại thời điểm đó.';
COMMENT ON COLUMN deliveries.pit_amount IS 'Thuế TNCN ước tính trên driver_fee — chốt lúc giao xong theo driver_finance_settings.pit_rate tại thời điểm đó.';
COMMENT ON COLUMN deliveries.driver_payout IS 'Số tiền tài xế THỰC NHẬN cho chuyến này = driver_fee - commission_amount - vat_amount - pit_amount — đúng bằng phần thực tế cộng vào ví lúc giao xong.';

-- update_delivery_status(): chữ ký + toàn bộ thân hàm giữ nguyên hofa-db/69_driver_wallet_vi_tren.sql,
-- chỉ mở rộng khối "Cộng ví" ở nhánh 'delivered' để tính thêm vat_amount/pit_amount và lưu lại
-- 4 cột breakdown lên deliveries.
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
  v_vat_rate NUMERIC;
  v_pit_rate NUMERIC;
  v_commission_amount INTEGER;
  v_vat_amount INTEGER;
  v_pit_amount INTEGER;
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
    -- mọi phương thức thanh toán. Ví thu nhập: COD không cộng gì; chuyển khoản/đã xác nhận
    -- thanh toán online thì cộng NGUYÊN total_amount. Phần tài xế thực nhận (driver_payout) giờ
    -- trừ cả hoa hồng LẪN thuế GTGT/TNCN — cùng công thức với merchant_payout (hofa-db/67), lưu
    -- lại 4 cột breakdown lên deliveries để hiển thị rõ ở app tài xế thay vì chỉ trừ ẩn vào ví.
    IF v_delivery.earning_credited_at IS NULL THEN
      SELECT payment_method, total_amount INTO v_order_payment_method, v_order_total
        FROM orders WHERE id = v_delivery.order_id;
      SELECT driver_fee_commission_rate, vat_rate, pit_rate
        INTO v_commission_rate, v_vat_rate, v_pit_rate
        FROM driver_finance_settings ORDER BY updated_at DESC LIMIT 1;
      v_commission_rate := COALESCE(v_commission_rate, 0);
      v_vat_rate := COALESCE(v_vat_rate, 0);
      v_pit_rate := COALESCE(v_pit_rate, 0);
      v_commission_amount := ROUND(v_delivery.driver_fee * v_commission_rate / 100.0);
      v_vat_amount := ROUND(v_delivery.driver_fee * v_vat_rate / 100.0);
      v_pit_amount := ROUND(v_delivery.driver_fee * v_pit_rate / 100.0);
      v_driver_fee_net := v_delivery.driver_fee - v_commission_amount - v_vat_amount - v_pit_amount;

      INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, order_id)
      VALUES (v_delivery.driver_id, 'cod', 'order_deducted', -(v_order_total - v_driver_fee_net), v_delivery.order_id);

      IF v_order_payment_method <> 'cod' THEN
        INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, delivery_id)
        VALUES (v_delivery.driver_id, 'earning', 'order_payment_received', v_order_total, p_delivery_id);
      END IF;

      UPDATE deliveries SET
        cod_credited_at = now(), earning_credited_at = now(),
        commission_amount = v_commission_amount, vat_amount = v_vat_amount,
        pit_amount = v_pit_amount, driver_payout = v_driver_fee_net
      WHERE id = p_delivery_id;
    END IF;
  ELSIF p_new_status = 'failed' THEN
    UPDATE drivers SET status = 'online' WHERE id = v_delivery.driver_id;
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION update_delivery_status IS
  'Đổi trạng thái chuyến giao, kiểm OTP (trừ picked_up của đơn mua hộ — dùng ảnh thay OTP), đồng bộ trạng thái đơn, trừ kho thật lúc lấy hàng, cộng/trừ ví tài xế lúc giao xong (Ví trên luôn trừ, Ví thu nhập chỉ cộng cho đơn không phải COD) và lúc mua xong nếu là đơn mua hộ, lưu breakdown hoa hồng/thuế GTGT/TNCN lên deliveries — xem hofa-db/72_driver_tax_rates.sql.';

-- Backfill chuyến ĐÃ giao trước migration này — khôi phục đúng commission_amount/driver_payout
-- ĐÃ THỰC SỰ áp dụng, đọc ngược từ dòng sổ cái 'order_deducted' đã ghi (không đoán):
-- driver_fee_net = order_total + order_deducted.amount (amount đã âm sẵn).
UPDATE deliveries d
SET driver_payout = o.total_amount + t.amount,
    commission_amount = d.driver_fee - (o.total_amount + t.amount)
FROM orders o, driver_wallet_transactions t
WHERE d.order_id = o.id
  AND t.order_id = o.id AND t.wallet = 'cod' AND t.entry_type = 'order_deducted'
  AND d.status = 'delivered' AND d.driver_payout = 0 AND d.commission_amount = 0;
