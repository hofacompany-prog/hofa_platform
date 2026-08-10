-- ============================================================================
-- MIGRATION 64 — Sổ cái ví cửa hàng, cùng tinh thần hofa-db/62_driver_wallet_ledger.sql
--
-- Trước đây orders.commission_amount/merchant_payout chỉ là số TÍNH SẴN lúc tạo đơn (create_order),
-- không hề gắn với trạng thái đơn — "doanh thu" ở màn Tài chính (store app) tính trên MỌI đơn
-- chưa huỷ ngay từ lúc đặt, kể cả đơn còn đang chuẩn bị/chưa giao. Giờ đổi giống bên tài xế:
-- tiền cửa hàng CHỈ được cộng (ghi vào sổ cái) SAU KHI đơn đã ở trạng thái 'delivered' — số tiền
-- cộng = merchant_payout (đã trừ hoa hồng HOFA từ lúc tạo đơn, xem orders.commission_amount).
--
-- Không có luồng rút tiền/đối soát cho cửa hàng ở đợt này (HOFA không giữ tiền hộ cửa hàng theo
-- thiết kế hiện tại — xem comment đầu hofa_store_app/lib/screens/finance/finance_screen.dart) —
-- sổ cái này chỉ để "Tài chính" (store app)/tương lai có nguồn số liệu ĐÚNG, có thể truy vết
-- theo đơn, thay vì tính lại (đôi khi sai lệch nếu commission_rate cửa hàng từng đổi).
-- ============================================================================

BEGIN;

CREATE TABLE merchant_wallet_transactions (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id  UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  entry_type   TEXT NOT NULL CHECK (entry_type IN ('order_payout')),
  amount       INTEGER NOT NULL CHECK (amount <> 0),  -- luôn dương ở bản đầu (chỉ có order_payout)
  order_id     UUID REFERENCES orders(id),
  note         TEXT,
  created_by   UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE merchant_wallet_transactions IS
  'Sổ cái ví cửa hàng — nguồn sự thật cho "doanh thu ròng" (xem view merchant_wallet_balances). entry_type=order_payout insert đúng 1 lần khi đơn chuyển sang delivered (xem update_order_status, hofa-db/04_api_functions.sql), amount = orders.merchant_payout tại thời điểm giao (đã trừ hoa hồng).';

CREATE INDEX idx_merchant_wallet_tx_merchant ON merchant_wallet_transactions (merchant_id, created_at DESC);
CREATE INDEX idx_merchant_wallet_tx_order ON merchant_wallet_transactions (order_id);

CREATE VIEW merchant_wallet_balances AS
  SELECT merchant_id, COALESCE(SUM(amount), 0)::INTEGER AS balance
    FROM merchant_wallet_transactions
   GROUP BY merchant_id;
COMMENT ON VIEW merchant_wallet_balances IS
  'Tổng thu nhập ròng (đã trừ hoa hồng) cửa hàng đã được ghi nhận, tính động từ merchant_wallet_transactions.';

-- Cờ chống chạy trùng — cùng cơ chế deliveries.cod_credited_at/earning_credited_at (migration 62).
ALTER TABLE orders ADD COLUMN merchant_credited_at TIMESTAMPTZ;
COMMENT ON COLUMN orders.merchant_credited_at IS
  'Thời điểm đã insert dòng order_payout vào merchant_wallet_transactions — chống cộng đúp nếu status delivered bị replay (update_order_status gọi p_force=true từ update_delivery_status).';

-- update_order_status(): chữ ký + toàn bộ logic state-machine/huỷ đơn giữ nguyên y hệt bản gốc
-- (hofa-db/04_api_functions.sql), chỉ thêm đúng 1 khối: cộng sổ cái cửa hàng khi chuyển sang
-- 'delivered'.
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
  -- cộng đúp nếu status delivered bị replay qua p_force.
  IF p_new_status = 'delivered' AND NOT v_already_credited THEN
    INSERT INTO merchant_wallet_transactions (merchant_id, entry_type, amount, order_id)
    VALUES (v_order.merchant_id, 'order_payout', v_order.merchant_payout, v_order.id);
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
  'Đổi trạng thái đơn theo đúng state machine, tự nhả tồn kho khi huỷ, ghi lại ai đổi, cộng sổ cái cửa hàng (merchant_wallet_transactions) khi chuyển sang delivered — xem hofa-db/64_merchant_wallet_ledger.sql.';

COMMIT;
