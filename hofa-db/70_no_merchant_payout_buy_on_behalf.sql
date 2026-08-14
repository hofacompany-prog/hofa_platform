-- ============================================================================
-- MIGRATION 70 — Cửa hàng "mua hộ" (merchant_type='buy_on_behalf') KHÔNG được cộng
-- merchant_payout vào sổ cái nữa.
--
-- Lý do: cửa hàng mua hộ không thật sự bán/giao hàng từ kho của mình — tài xế tự đi mua hộ ở
-- bất kỳ đâu rồi được hoàn tiền hàng thẳng vào ví (wallet='earning', entry_type=
-- 'buy_on_behalf_reimbursement', xem update_delivery_status trong
-- hofa-db/69_driver_wallet_vi_tren.sql). Trước migration này, update_order_status() vẫn cộng
-- merchant_payout (subtotal đã trừ hoa hồng/thuế) vào ví cửa hàng 'mua hộ' y hệt cửa hàng
-- thường — sai vì cửa hàng đó không hề bỏ vốn/hàng ra để nhận lại tiền này, thực chất là cộng
-- khống.
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
  v_already_credited BOOLEAN;
  v_merchant_type merchant_type;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy đơn hàng' USING ERRCODE = 'no_data_found';
  END IF;
  v_already_credited := v_order.merchant_credited_at IS NOT NULL;

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
    cancelled_by  = CASE WHEN p_new_status = 'cancelled' THEN p_changed_by ELSE cancelled_by END,
    merchant_credited_at = CASE WHEN p_new_status = 'delivered' AND merchant_credited_at IS NULL
                                 THEN now() ELSE merchant_credited_at END
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  -- Cộng sổ cái cửa hàng — CHỈ lúc chuyển sang 'delivered', đúng bằng merchant_payout đã chốt
  -- lúc tạo đơn (đã trừ hoa hồng). Guard v_already_credited (đọc TRƯỚC UPDATE ở trên) chống
  -- cộng đúp nếu status delivered bị replay qua p_force. Cửa hàng mua hộ (merchant_type=
  -- 'buy_on_behalf') KHÔNG được cộng — không thật sự bán/giao hàng từ kho mình, tài xế đã được
  -- hoàn tiền hàng riêng (buy_on_behalf_reimbursement, xem hofa-db/69_driver_wallet_vi_tren.sql).
  IF p_new_status = 'delivered' AND NOT v_already_credited THEN
    SELECT merchant_type INTO v_merchant_type FROM merchants WHERE id = v_order.merchant_id;
    IF v_merchant_type <> 'buy_on_behalf' THEN
      INSERT INTO merchant_wallet_transactions (merchant_id, entry_type, amount, order_id)
      VALUES (v_order.merchant_id, 'order_payout', v_order.merchant_payout, v_order.id);
    END IF;
  END IF;

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
  'Chuyển trạng thái đơn theo state machine (hoặc ép qua p_force), cộng sổ cái cửa hàng đúng 1 lần lúc delivered — TRỪ cửa hàng mua hộ (merchant_type=buy_on_behalf), xem hofa-db/70_no_merchant_payout_buy_on_behalf.sql.';
