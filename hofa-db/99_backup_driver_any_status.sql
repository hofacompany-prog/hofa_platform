-- ============================================================================
-- MIGRATION 99 — Tài xế dự phòng (is_backup_driver=true) được gán đơn BẤT KỂ đang ở trạng thái
-- nào (offline/busy/on_break/online), không riêng lúc online như tài xế thường — assign_driver
-- (hofa-db/98_backup_driver_pool.sql) đang RAISE EXCEPTION nếu status khác 'online' nên chặn
-- oan nhóm dự phòng. Tìm tài xế dự phòng phía server (findNearestOnlineDriver, backupPool=true)
-- cũng đã bỏ điều kiện status='online' tương ứng, xem server/src/dispatch.js.
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
  v_is_backup BOOLEAN;
  v_driver_status driver_status;
BEGIN
  -- order_status_history.changed_by trỏ tới users(id), không phải drivers(id) —
  -- phải tra ra user_id thật của tài xế trước khi ghi lịch sử đơn hàng.
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
                          assigned_at, pickup_otp, delivery_otp)
  VALUES (p_order_id, p_driver_id, 'assigned', p_distance_km, p_eta_minutes, p_driver_fee,
          now(), gen_otp(), gen_otp())
  ON CONFLICT (order_id) DO UPDATE SET
    driver_id = p_driver_id, status = 'assigned', distance_km = p_distance_km,
    eta_minutes = p_eta_minutes, driver_fee = p_driver_fee, assigned_at = now()
  RETURNING * INTO v_delivery;

  IF NOT v_is_backup THEN
    UPDATE drivers SET status = 'busy' WHERE id = p_driver_id;
  END IF;

  SELECT status INTO v_order_status FROM orders WHERE id = p_order_id;
  IF v_order_status IS DISTINCT FROM 'assigned' THEN
    PERFORM update_order_status(p_order_id, 'assigned', v_driver_user_id, 'driver', 'Đã gán tài xế');
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION assign_driver IS
  'Gán tài xế cho đơn — tài xế thường phải đang online mới gán được; tài xế dự phòng
   (is_backup_driver=true) được gán BẤT KỂ trạng thái nào và không bị chuyển sang busy, giữ
   nguyên trạng thái hiện tại để luôn sẵn sàng nhận thêm đơn khác, xem
   hofa-db/99_backup_driver_any_status.sql.';
