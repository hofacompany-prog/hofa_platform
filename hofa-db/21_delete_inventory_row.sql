-- Cho phép xoá hẳn 1 dòng tồn kho (vd sản phẩm ngừng bán ở chi nhánh này, hoặc dòng tạo
-- nhầm) khỏi màn "Kho hàng" — trước giờ chỉ có apply_stock_movement() để ĐIỀU CHỈNH số
-- lượng, không có cách xoá dòng.
--
-- An toàn 2 lớp, giữ đúng nguyên tắc "apply_stock_movement là cách DUY NHẤT đổi tồn kho":
--   1. Chặn xoá nếu quantity_reserved > 0 (đang giữ chỗ cho đơn hàng chưa giao) — xoá lúc
--      này sẽ làm mất dấu vết số đang giữ, release_inventory() sau này sẽ không tìm thấy
--      dòng để nhả lại.
--   2. Nếu quantity_on_hand > 0, tự ghi 1 dòng stock_movements điều chỉnh về 0 TRƯỚC khi
--      xoá, để sổ sách không bị "biến mất" một khoản tồn kho mà không có lý do ghi lại.
BEGIN;

CREATE OR REPLACE FUNCTION delete_inventory_row(
  p_branch_id  UUID,
  p_variant_id UUID,
  p_user_id    UUID DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_row inventory;
BEGIN
  SELECT * INTO v_row FROM inventory
   WHERE branch_id = p_branch_id AND variant_id = p_variant_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy dòng tồn kho này' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_row.quantity_reserved > 0 THEN
    RAISE EXCEPTION 'Không thể xoá — đang giữ % phần cho đơn hàng chưa giao xong', v_row.quantity_reserved
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_row.quantity_on_hand > 0 THEN
    INSERT INTO stock_movements (
      branch_id, variant_id, move_type, quantity, balance_after,
      reference_type, created_by, note
    ) VALUES (
      p_branch_id, p_variant_id, 'adjustment', -v_row.quantity_on_hand, 0,
      'manual', p_user_id, 'Tự động điều chỉnh về 0 trước khi xoá khỏi kho'
    );
  END IF;

  DELETE FROM inventory WHERE branch_id = p_branch_id AND variant_id = p_variant_id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION delete_inventory_row IS
  'Xoá 1 dòng tồn kho khỏi màn quản lý — chặn nếu đang giữ chỗ cho đơn hàng (quantity_reserved > 0), tự ghi 1 dòng stock_movements điều chỉnh về 0 trước khi xoá nếu còn tồn thật (quantity_on_hand > 0) để không phá sổ sách';

COMMIT;
