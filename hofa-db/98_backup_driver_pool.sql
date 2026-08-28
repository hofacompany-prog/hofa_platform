-- ============================================================================
-- MIGRATION 98 — "Tài xế dự phòng" (backup pool): 1 nhóm tài xế đánh dấu riêng, nhận KHÔNG
-- GIỚI HẠN số đơn cùng lúc (không bị chuyển 'busy' khi được gán, luôn sẵn sàng nhận thêm) —
-- CHỈ dùng làm phương án dự phòng khi offerToNearestDriver không tìm được tài xế thường nào
-- (status='online', is_backup_driver=false) nhận đơn, xem server/src/dispatch.js. Admin bật/tắt
-- cả nhóm bằng driver_dispatch_settings.backup_pool_enabled — tắt thì nhóm này coi như không
-- tồn tại với dispatch, dù từng tài xế vẫn giữ nguyên cờ is_backup_driver.
-- ============================================================================

ALTER TABLE drivers ADD COLUMN IF NOT EXISTS is_backup_driver BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN drivers.is_backup_driver IS
  'true = thuộc nhóm tài xế dự phòng — nhận KHÔNG GIỚI HẠN đơn cùng lúc (assign_driver không
   chuyển status sang busy), chỉ được mời khi tìm tài xế thường (is_backup_driver=false, status=
   online) thất bại VÀ driver_dispatch_settings.backup_pool_enabled=true. Admin bật/tắt qua
   PATCH /admin/drivers/:id (màn "Tài xế dự phòng", hofa_admin_app).';

ALTER TABLE driver_dispatch_settings ADD COLUMN IF NOT EXISTS backup_pool_enabled BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN driver_dispatch_settings.backup_pool_enabled IS
  'Công tắc bật/tắt CẢ NHÓM tài xế dự phòng (drivers.is_backup_driver=true) — tắt thì
   offerToNearestDriver không bao giờ thử nhóm này dù có tài xế đang bật cờ, xem
   server/src/dispatch.js.';

-- Cập nhật assign_driver: tài xế dự phòng KHÔNG chuyển sang 'busy' khi được gán, giữ nguyên
-- 'online' để có thể nhận thêm đơn khác ngay lập tức (khác tài xế thường chỉ nhận 1 đơn/lần).
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
BEGIN
  -- order_status_history.changed_by trỏ tới users(id), không phải drivers(id) —
  -- phải tra ra user_id thật của tài xế trước khi ghi lịch sử đơn hàng.
  SELECT user_id, is_backup_driver INTO v_driver_user_id, v_is_backup
    FROM drivers WHERE id = p_driver_id AND status = 'online';
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
  'Gán tài xế cho đơn — tài xế dự phòng (is_backup_driver=true) KHÔNG bị chuyển status sang busy,
   giữ nguyên online để nhận thêm đơn khác ngay, xem hofa-db/98_backup_driver_pool.sql.';
