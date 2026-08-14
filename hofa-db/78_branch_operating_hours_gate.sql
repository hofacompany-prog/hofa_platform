-- ============================================================================
-- MIGRATION 78 — Giờ hoạt động (branch_hours) thật sự có tác dụng: chi nhánh coi như ĐÓNG nếu
-- ngoài khung giờ đã cấu hình, KẾT HỢP với công tắc thủ công is_open (nay đổi ý nghĩa thành
-- "Tạm nghỉ" có hẹn giờ — cột break_until mới). Trạng thái hiệu lực tính LIVE qua hàm
-- branch_effective_status(), không cần cron: 'open' | 'on_break' | 'closed_hours'.
--
-- break_until NULL khi is_open=false = tạm nghỉ VÔ THỜI HẠN — giữ đúng hành vi tắt tay cũ (kể cả
-- chỗ hệ thống tự tắt khi cửa hàng không xác nhận đơn kịp, xem order_detail_screen.dart
-- _cancelDueToTimeout ở app Cửa hàng — không đổi call site đó, vẫn gọi toggle không kèm hẹn giờ).
--
-- Chi nhánh CHƯA từng cấu hình branch_hours (0 dòng) → luôn coi là 'open' nếu is_open=true —
-- an toàn ngược, không đột ngột khoá các chi nhánh chưa set giờ hoạt động.
-- ============================================================================

ALTER TABLE branches ADD COLUMN break_until TIMESTAMPTZ NULL;
COMMENT ON COLUMN branches.break_until IS
  'Thời điểm tự mở lại sau khi bấm "Tạm nghỉ" có hẹn giờ (is_open=false). NULL = tạm nghỉ vô thời hạn (đóng tay không hẹn giờ, hoặc hệ thống tự đóng do không xác nhận đơn kịp) — phải tự bật lại. Không có cron nào dọn cột này, branch_effective_status() tự tính live theo now().';

CREATE OR REPLACE FUNCTION branch_effective_status(p_branch_id UUID) RETURNS TEXT AS $$
DECLARE
  v_is_open     BOOLEAN;
  v_break_until TIMESTAMPTZ;
  v_now_local   TIMESTAMP;
  v_weekday     SMALLINT;
  v_has_hours   BOOLEAN;
  v_within      BOOLEAN;
BEGIN
  SELECT is_open, break_until INTO v_is_open, v_break_until FROM branches WHERE id = p_branch_id;
  IF NOT FOUND THEN
    RETURN 'open'; -- an toàn nếu lỡ gọi sai id, không chặn oan
  END IF;

  IF NOT v_is_open AND (v_break_until IS NULL OR v_break_until > now()) THEN
    RETURN 'on_break';
  END IF;

  v_now_local := now() AT TIME ZONE 'Asia/Ho_Chi_Minh';
  v_weekday := EXTRACT(DOW FROM v_now_local)::SMALLINT;

  SELECT EXISTS(SELECT 1 FROM branch_hours WHERE branch_id = p_branch_id) INTO v_has_hours;
  IF NOT v_has_hours THEN
    RETURN 'open'; -- chưa cấu hình giờ hoạt động — không giới hạn, giữ hành vi cũ
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM branch_hours
     WHERE branch_id = p_branch_id AND weekday = v_weekday
       AND v_now_local::time BETWEEN open_time AND close_time
  ) INTO v_within;

  RETURN CASE WHEN v_within THEN 'open' ELSE 'closed_hours' END;
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION branch_effective_status IS
  'Trạng thái hiệu lực của 1 chi nhánh: open (đang mở) | on_break (đang tạm nghỉ, is_open=false còn hạn break_until) | closed_hours (ngoài khung giờ branch_hours hôm nay, không phải tạm nghỉ). Tính live theo now(), không cache/cron — xem hofa-db/78_branch_operating_hours_gate.sql.';
