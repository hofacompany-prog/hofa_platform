-- Tồn kho mặc định của cửa hàng — biến thể CHƯA từng có dòng inventory (chưa ai đặt tồn kho
-- riêng, kể cả qua GAS lẫn màn "Kho hàng" app Cửa hàng) sẽ tự dùng số này làm quantity_on_hand
-- ban đầu ngay lần đặt hàng ĐẦU TIÊN, thay vì luôn là 0 (chặn bán) như hành vi cũ — xem
-- reserve_inventory() sửa lại bên dưới. NULL (mặc định, chưa cấu hình) = giữ NGUYÊN hành vi cũ
-- (coi như 0), không đổi gì cho cửa hàng chưa bật tính năng này.
--
-- Đây chỉ là giá trị GIEO 1 LẦN lúc dòng inventory được tạo — sau đó dòng inventory là nguồn sự
-- thật duy nhất (tăng/giảm bình thường qua bán hàng/điều chỉnh kho), đổi tồn kho mặc định của
-- cửa hàng sau đó KHÔNG ảnh hưởng ngược lại các biến thể đã có dòng inventory rồi.
ALTER TABLE merchants ADD COLUMN default_stock_quantity INTEGER;
ALTER TABLE merchants ADD CONSTRAINT merchants_default_stock_quantity_valid
  CHECK (default_stock_quantity IS NULL OR default_stock_quantity >= 0);
COMMENT ON COLUMN merchants.default_stock_quantity IS
  'Tồn kho mặc định cho biến thể chưa từng cài tồn kho riêng (NULL = coi như 0, giữ hành vi cũ) — chỉ dùng làm giá trị gieo lúc tạo dòng inventory đầu tiên cho biến thể đó, xem reserve_inventory()';

-- CREATE OR REPLACE — chữ ký giữ nguyên 3 tham số như hofa-db/04_api_functions.sql, không cần
-- sửa nơi gọi. Chỉ đổi đúng giá trị gieo lúc tự tạo dòng inventory còn thiếu (trước đây luôn là
-- 0) sang tồn kho mặc định của cửa hàng (COALESCE về 0 nếu merchant chưa cấu hình) — mọi logic
-- khoá dòng/kiểm tra đủ hàng/reserve còn lại giữ NGUYÊN VẸN như bản gốc.
CREATE OR REPLACE FUNCTION reserve_inventory(
  p_branch_id UUID,
  p_variant_id UUID,
  p_quantity INTEGER
) RETURNS VOID AS $$
DECLARE
  v_available INTEGER;
  v_default_qty INTEGER;
BEGIN
  SELECT COALESCE(m.default_stock_quantity, 0) INTO v_default_qty
    FROM branches b JOIN merchants m ON m.id = b.merchant_id
   WHERE b.id = p_branch_id;

  INSERT INTO inventory (branch_id, variant_id, quantity_on_hand)
  VALUES (p_branch_id, p_variant_id, COALESCE(v_default_qty, 0))
  ON CONFLICT (branch_id, variant_id) DO NOTHING;

  SELECT (quantity_on_hand - quantity_reserved) INTO v_available
  FROM inventory WHERE branch_id = p_branch_id AND variant_id = p_variant_id
  FOR UPDATE;

  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Không đủ hàng tồn kho (còn %, cần %)', v_available, p_quantity
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE inventory SET quantity_reserved = quantity_reserved + p_quantity
  WHERE branch_id = p_branch_id AND variant_id = p_variant_id;
END;
$$ LANGUAGE plpgsql;
