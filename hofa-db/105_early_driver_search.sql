-- ============================================================================
-- MIGRATION 105 — Tìm tài xế SỚM thay vì đợi tới khi món làm xong hẳn (ready_for_pickup):
-- (1) driver_dispatch_settings.search_before_ready_minutes — admin cấu hình số phút "còn bấy
--     nhiêu phút nữa là sẵn sàng" thì bắt đầu tìm tài xế trước, để tài xế có thời gian tới quán
--     đúng lúc món vừa xong, giảm thời gian chờ đợi 2 phía.
-- (2) driver_dispatch_settings.search_on_confirm — công tắc "tối đa": bật thì bỏ qua hẳn thời
--     gian chuẩn bị, tìm tài xế NGAY lúc cửa hàng xác nhận đơn (status='confirmed').
-- Cả 2 cách đều tạo deliveries row + mời tài xế SỚM nhưng KHÔNG đẩy orders.status lên 'assigned'
-- ngay (assign_driver() nhận thêm p_defer_order_status=true) — giữ nguyên trạng thái 'confirmed'/
-- 'preparing' cho tới khi cửa hàng THẬT SỰ bấm "Đã làm xong", tránh phá vỡ cách phân nhóm tab
-- "Đang chuẩn bị"/"Đã làm xong" (orders_list_screen.dart _statusGroups) và điều kiện hiện nút
-- "Đã làm xong" (order_detail_screen.dart isPrepPhase) ở cả 2 app — cả 2 chỗ đó đều dựa thẳng
-- vào orders.status, đẩy sớm lên 'assigned' sẽ khiến đơn "biến mất" khỏi tab đang làm dù bếp
-- chưa xong. Khi cửa hàng bấm xong, PATCH /orders/:id/status (status='ready_for_pickup') tự
-- nhận ra đã có deliveries row rồi thì đẩy nốt sang 'assigned' luôn (chuyển ready_for_pickup→
-- assigned vẫn hợp lệ với state machine sẵn có, không cần sửa update_order_status).
--
-- Đồng thời thêm deliveries.pickup_eta_minutes — ETA tài xế TỚI CỬA HÀNG lúc gán (khác
-- eta_minutes hiện có = ETA CẢ CHUYẾN cửa hàng→khách, dùng tính driver_fee) — tính từ khoảng
-- cách tài xế hiện tại tới chi nhánh (findNearestOnlineDriver đã tính khoảng cách này để chọn
-- tài xế gần nhất, trước đây bị bỏ đi sau khi chọn xong, giờ giữ lại). Không cập nhật live theo
-- vị trí tài xế di chuyển sau đó (app tài xế chỉ chụp vị trí 1 lần lúc bấm nút, không theo dõi
-- nền liên tục) — chỉ là ước lượng tại đúng thời điểm gán.
-- ============================================================================

ALTER TABLE driver_dispatch_settings
  ADD COLUMN IF NOT EXISTS search_before_ready_minutes INTEGER NOT NULL DEFAULT 5 CHECK (search_before_ready_minutes >= 0),
  ADD COLUMN IF NOT EXISTS search_on_confirm BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN driver_dispatch_settings.search_before_ready_minutes IS
  'Bắt đầu tìm tài xế khi thời gian chuẩn bị còn lại bấy nhiêu phút (tính từ confirmed_at +
   estimated_prep_minutes, hoặc default_prep_minutes/15 phút nếu chưa chốt estimated_prep_minutes)
   thay vì đợi cửa hàng bấm "Đã làm xong" — xem dispatch.sweepEarlyDriverSearch. Bỏ qua hẳn nếu
   search_on_confirm=true (tìm ngay lúc xác nhận, không đợi tới ngưỡng này).';
COMMENT ON COLUMN driver_dispatch_settings.search_on_confirm IS
  'true = tìm tài xế NGAY lúc cửa hàng xác nhận đơn (confirmed), bỏ qua hẳn
   search_before_ready_minutes — dùng khi muốn tài xế luôn có mặt sớm nhất có thể, chấp nhận tài
   xế phải chờ ở quán nếu bếp làm chậm hơn dự kiến.';

ALTER TABLE deliveries ADD COLUMN pickup_eta_minutes INTEGER;
COMMENT ON COLUMN deliveries.pickup_eta_minutes IS
  'ETA (phút) tài xế dự kiến tới CỬA HÀNG để lấy hàng, tính từ vị trí tài xế lúc được gán — khác
   eta_minutes (ETA cả chuyến cửa hàng→khách, dùng tính driver_fee). Chỉ là ước lượng tại thời
   điểm gán, không cập nhật live theo vị trí tài xế di chuyển sau đó.';

-- assign_driver: thêm p_pickup_eta_minutes (ETA tới cửa hàng) + p_defer_order_status (true = tìm
-- tài xế SỚM, chưa đẩy orders.status lên 'assigned' vội — xem ghi chú migration ở trên). Giữ
-- nguyên hành vi cũ hệt trước đây nếu gọi không truyền 2 tham số mới (mặc định NULL/false).
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

  IF NOT p_defer_order_status THEN
    SELECT status INTO v_order_status FROM orders WHERE id = p_order_id;
    IF v_order_status IS DISTINCT FROM 'assigned' THEN
      PERFORM update_order_status(p_order_id, 'assigned', v_driver_user_id, 'driver', 'Đã gán tài xế');
    END IF;
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION assign_driver IS
  'Gán tài xế cho đơn — tài xế thường phải đang online mới gán được; tài xế dự phòng
   (is_backup_driver=true) được gán BẤT KỂ trạng thái nào và không bị chuyển sang busy, giữ
   nguyên trạng thái hiện tại để luôn sẵn sàng nhận thêm đơn khác. p_pickup_eta_minutes = ETA
   tới cửa hàng. p_defer_order_status=true = tìm tài xế SỚM (trước ready_for_pickup), CHƯA đẩy
   orders.status lên assigned — nơi gọi (PATCH /orders/:id/status, status=ready_for_pickup) tự
   đẩy nốt khi cửa hàng thật sự bấm "Đã làm xong". Xem hofa-db/105_early_driver_search.sql.';
