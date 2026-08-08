-- Đơn ở cửa hàng mua hộ (merchant_type='buy_on_behalf') bỏ qua bước cửa hàng xác nhận/chuẩn bị
-- (cửa hàng không làm gì cả, tài xế là người trực tiếp đi mua) — server tự chuyển thẳng đơn
-- sang ready_for_pickup rồi gọi dispatch ngay khi thanh toán được ghi nhận (xem
-- server/src/orderOffer.js dispatchBuyOnBehalfOrder). File này chỉ lo phần DB: bỏ OTP ở bước
-- "picked_up" cho đơn mua hộ (không có nhân viên cửa hàng nào đọc OTP cho tài xế) và hoàn tiền
-- hàng tài xế đã ứng ra mua ngay lúc đó.

ALTER TABLE deliveries ADD COLUMN reimbursed_at TIMESTAMPTZ;
COMMENT ON COLUMN deliveries.reimbursed_at IS
  'Thời điểm cộng ví tài xế tiền hàng đã ứng mua hộ (chỉ áp dụng đơn merchant_type=buy_on_behalf) — tránh cộng 2 lần nếu status bị replay';

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
    -- reimbursed_at (v_delivery ở đây là bản TRƯỚC UPDATE reimbursed_at nên vẫn đọc đúng).
    IF v_merchant_type = 'buy_on_behalf' AND v_delivery.reimbursed_at IS NULL THEN
      UPDATE drivers SET wallet_balance = wallet_balance + COALESCE(v_order_subtotal, 0)
       WHERE id = v_delivery.driver_id;
      UPDATE deliveries SET reimbursed_at = now() WHERE id = p_delivery_id;
    END IF;
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
  'Đổi trạng thái chuyến giao, kiểm OTP (trừ picked_up của đơn mua hộ — dùng ảnh thay OTP), đồng bộ trạng thái đơn, trừ kho thật lúc lấy hàng, cộng ví tài xế lúc giao xong (và lúc mua xong nếu là đơn mua hộ)';
