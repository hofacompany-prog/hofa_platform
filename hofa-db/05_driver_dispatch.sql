-- ============================================================================
-- Hỗ trợ điều phối đơn tự động cho app tài xế (giống Grab/Shopee):
-- hệ thống tự tìm tài xế gần nhất khi đơn "ready_for_pickup", tài xế bật
-- "tự động nhận đơn" thì được gán thẳng, tài xế thường phải xác nhận trong
-- 1 khung giờ ngắn — quá hạn hoặc từ chối thì tự chuyển sang tài xế kế tiếp.
--
-- Chạy file này 1 lần trong Supabase SQL Editor (đã đồng bộ vào 01_schema.sql
-- để những lần cài đặt mới không cần chạy lại file này).
-- ============================================================================

ALTER TABLE drivers
  ADD COLUMN IF NOT EXISTS auto_accept BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN drivers.auto_accept IS 'true = hệ thống tự gán đơn, không cần xác nhận';

ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS accept_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS declined_driver_ids UUID[] NOT NULL DEFAULT '{}';
COMMENT ON COLUMN deliveries.accept_deadline IS 'Hạn tài xế xác nhận nhận đơn (chỉ áp dụng khi driver.auto_accept = false)';
COMMENT ON COLUMN deliveries.declined_driver_ids IS 'Tài xế đã từ chối/hết hạn — loại khỏi lần gán tiếp theo';

-- Cập nhật assign_driver: chỉ đổi order_status ở lần gán ĐẦU TIÊN, để có thể gọi lại
-- hàm này khi tự động chuyển đơn sang tài xế khác (order vẫn đang ở 'assigned').
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
BEGIN
  IF NOT EXISTS (SELECT 1 FROM drivers WHERE id = p_driver_id AND status = 'online') THEN
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

  SELECT status INTO v_order_status FROM orders WHERE id = p_order_id;
  IF v_order_status IS DISTINCT FROM 'assigned' THEN
    PERFORM update_order_status(p_order_id, 'assigned', p_driver_id, 'driver', 'Đã gán tài xế');
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;
