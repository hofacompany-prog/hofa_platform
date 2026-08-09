-- Đổi "Xoá cửa hàng" ở admin từ xoá mềm sang xoá THẬT (DELETE hẳn khỏi Postgres) — quyết định
-- có chủ đích: người dùng đã được cảnh báo rõ xoá mềm trước đây không thực sự "đóng" được cửa
-- hàng (chi nhánh/sản phẩm vẫn còn is_open/is_active, khách vẫn đặt được hàng), và đã xác nhận
-- chấp nhận đánh đổi MẤT VĨNH VIỄN toàn bộ đơn hàng/thanh toán/đánh giá của cửa hàng đó để đổi
-- lấy việc xoá thật sự dứt điểm.
--
-- branches/products đã ON DELETE CASCADE từ merchants sẵn (xem 01_schema.sql) — chỉ cần nới
-- các ràng buộc ĐANG CHẶN việc xoá đó thành CASCADE:
--   - orders.merchant_id / orders.branch_id: RESTRICT -> CASCADE (chặn xoá nếu cửa hàng/chi
--     nhánh từng có bất kỳ đơn nào — trường hợp thường gặp nhất khi admin muốn xoá 1 cửa hàng
--     thật, nên bắt buộc phải nới mới xoá được)
--   - payments.order_id: RESTRICT -> CASCADE (chặn xoá đơn nếu đơn có giao dịch thanh toán —
--     nới để đơn cascade xong thì thanh toán cũng cascade theo)
--   - stock_movements.branch_id / stock_movements.variant_id: RESTRICT -> CASCADE (bảng ghi sổ
--     kho — comment gốc "không bao giờ sửa, chỉ thêm" — chặn xoá chi nhánh/biến thể nếu từng có
--     phát sinh kho; nới để xoá chi nhánh/sản phẩm không bị chặn giữa chừng. Hệ quả: sổ kho của
--     cửa hàng bị xoá cũng mất theo, không chỉ đơn/thanh toán/đánh giá).
--
-- Không đổi tên bừa constraint — tự tra đúng tên ràng buộc hiện có trên từng cột rồi drop, để
-- không phụ thuộc giả định tên constraint mặc định của Postgres.
DO $$
DECLARE
  v_conname TEXT;
BEGIN
  -- orders.merchant_id
  SELECT c.conname INTO v_conname FROM pg_constraint c
   WHERE c.conrelid = 'orders'::regclass AND c.contype = 'f'
     AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'orders'::regclass AND attname = 'merchant_id')]::smallint[];
  IF v_conname IS NOT NULL THEN EXECUTE format('ALTER TABLE orders DROP CONSTRAINT %I', v_conname); END IF;

  -- orders.branch_id
  SELECT c.conname INTO v_conname FROM pg_constraint c
   WHERE c.conrelid = 'orders'::regclass AND c.contype = 'f'
     AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'orders'::regclass AND attname = 'branch_id')]::smallint[];
  IF v_conname IS NOT NULL THEN EXECUTE format('ALTER TABLE orders DROP CONSTRAINT %I', v_conname); END IF;

  -- payments.order_id
  SELECT c.conname INTO v_conname FROM pg_constraint c
   WHERE c.conrelid = 'payments'::regclass AND c.contype = 'f'
     AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'payments'::regclass AND attname = 'order_id')]::smallint[];
  IF v_conname IS NOT NULL THEN EXECUTE format('ALTER TABLE payments DROP CONSTRAINT %I', v_conname); END IF;

  -- stock_movements.branch_id
  SELECT c.conname INTO v_conname FROM pg_constraint c
   WHERE c.conrelid = 'stock_movements'::regclass AND c.contype = 'f'
     AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'stock_movements'::regclass AND attname = 'branch_id')]::smallint[];
  IF v_conname IS NOT NULL THEN EXECUTE format('ALTER TABLE stock_movements DROP CONSTRAINT %I', v_conname); END IF;

  -- stock_movements.variant_id
  SELECT c.conname INTO v_conname FROM pg_constraint c
   WHERE c.conrelid = 'stock_movements'::regclass AND c.contype = 'f'
     AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'stock_movements'::regclass AND attname = 'variant_id')]::smallint[];
  IF v_conname IS NOT NULL THEN EXECUTE format('ALTER TABLE stock_movements DROP CONSTRAINT %I', v_conname); END IF;
END $$;

ALTER TABLE orders ADD CONSTRAINT orders_merchant_id_fkey
  FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE;
ALTER TABLE orders ADD CONSTRAINT orders_branch_id_fkey
  FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;
ALTER TABLE payments ADD CONSTRAINT payments_order_id_fkey
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;
ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_branch_id_fkey
  FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;
ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_variant_id_fkey
  FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE;
