-- ============================================================================
-- MIGRATION 62 — Sổ cái ví tài xế (2 ví: COD + Thu nhập), thay driver.wallet_balance
--
-- Trước đây MỌI tiền tài xế dồn vào đúng 1 cột drivers.wallet_balance (âm = đang giữ COD,
-- dương = có thể rút) — 2 khái niệm khác hẳn nhau bị gộp làm một, không có lịch sử giao dịch,
-- không truy vết được theo đơn, và update_delivery_status() cộng tiền bằng UPDATE thô KHÔNG có
-- cờ chống chạy trùng (khác hẳn cơ chế reimbursed_at đã dùng cho đơn mua hộ ngay phía trên nó
-- trong cùng hàm) — gọi lại RPC 2 lần là cộng đúp. Đơn KHÔNG PHẢI COD thì driver_fee cũng
-- không hề được cộng ở đâu cả (tài xế chỉ được trả tiền khi đơn là COD) — vá cả 2 lỗ hổng này
-- trong cùng migration.
--
-- Thiết kế: 1 bảng sổ cái duy nhất (driver_wallet_transactions), tách theo cột wallet
-- ('cod'|'earning'), số dư mỗi ví = SUM(amount) các dòng có dấu (+/-) của ví đó (view
-- driver_wallet_balances). "COD phải đối soát/còn phải nộp" KHÔNG cần sổ riêng — chính là
-- cod_balance hiện tại (tài xế đang giữ bao nhiêu = đúng bấy nhiêu còn phải nộp lại HOFA).
--
-- drivers.wallet_balance KHÔNG bị xoá (tránh DDL phá vỡ ngoài dự kiến) nhưng từ nay không còn
-- route nào ghi vào cột này nữa — nguồn sự thật chuyển hẳn sang driver_wallet_balances.
-- ============================================================================

BEGIN;

COMMENT ON COLUMN drivers.wallet_balance IS
  'KHÔNG CÒN DÙNG (deprecated) — giữ cột lại để không phá dữ liệu cũ nhưng không route nào ghi/đọc nữa. Số dư thật xem view driver_wallet_balances (driver_wallet_transactions), xem hofa-db/62_driver_wallet_ledger.sql.';

-- Cấu hình toàn sàn: % HOFA cắt trên phí giao (driver_fee) + hạn mức COD được giữ trước khi bị
-- khoá rút tiền/khoá nhận đơn COD mới. Mặc định driver_fee_commission_rate = 0 (an toàn — không
-- tự động giảm thu nhập tài xế cho tới khi admin chủ động đặt tỷ lệ khác 0).
CREATE TABLE driver_finance_settings (
  id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_fee_commission_rate  NUMERIC(5,2) NOT NULL DEFAULT 0,
  cod_debt_limit              INTEGER NOT NULL DEFAULT 2000000,
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by                  UUID REFERENCES users(id) ON DELETE SET NULL,

  CONSTRAINT driver_finance_commission_valid CHECK (driver_fee_commission_rate >= 0 AND driver_fee_commission_rate <= 100),
  CONSTRAINT driver_finance_cod_limit_valid  CHECK (cod_debt_limit > 0)
);
COMMENT ON TABLE driver_finance_settings IS
  'Cấu hình tài chính tài xế toàn sàn — chỉ giữ 1 dòng đang áp dụng (dòng mới nhất theo updated_at), admin sửa qua GET/PATCH /driver-finance-settings.';
COMMENT ON COLUMN driver_finance_settings.driver_fee_commission_rate IS
  '% HOFA cắt trên driver_fee mỗi chuyến — tài xế thực nhận vào ví thu nhập = driver_fee - driver_fee*rate/100.';
COMMENT ON COLUMN driver_finance_settings.cod_debt_limit IS
  'Ngưỡng cod_balance (VNĐ) — vượt ngưỡng thì khoá rút tiền ví thu nhập VÀ không được gán đơn COD mới nữa (xem findNearestOnlineDriver, server/src/dispatch.js).';

INSERT INTO driver_finance_settings (driver_fee_commission_rate, cod_debt_limit) VALUES (0, 2000000);

-- Đối soát COD theo lô — tài xế chọn đúng các đơn COD đã giao để nộp lại 1 lần, thay hẳn cho
-- luồng "Nạp tiền" gộp trước đây (driver_wallet_deposits, migration 47 — giữ bảng lại không
-- xoá để không mất dữ liệu cũ, nhưng không còn entry point mới từ UI).
CREATE TABLE driver_cod_settlements (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id       UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  total_amount    INTEGER NOT NULL CHECK (total_amount > 0),
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed','rejected')),
  proof_image_url TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at    TIMESTAMPTZ,
  confirmed_by    UUID REFERENCES users(id) ON DELETE SET NULL,
  reject_reason   TEXT
);
COMMENT ON TABLE driver_cod_settlements IS
  'Yêu cầu nộp lại tiền COD của tài xế, gồm nhiều đơn chọn cùng lúc (xem driver_cod_settlement_items) — admin xác nhận đã nhận tiền thì mới trừ cod_balance (insert driver_wallet_transactions entry_type=cod_settled).';

CREATE TABLE driver_cod_settlement_items (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  settlement_id  UUID NOT NULL REFERENCES driver_cod_settlements(id) ON DELETE CASCADE,
  order_id       UUID NOT NULL REFERENCES orders(id),
  amount         INTEGER NOT NULL CHECK (amount > 0),

  UNIQUE (order_id, settlement_id)
);
COMMENT ON TABLE driver_cod_settlement_items IS
  'Từng đơn COD nằm trong 1 lần nộp — amount chốt từ orders.total_amount lúc tạo yêu cầu, không tin số tài xế tự nhập.';

-- Sổ cái — trung tâm của toàn bộ thiết kế. Mọi thay đổi số dư ví tài xế (cả 2 ví) PHẢI đi qua
-- 1 dòng insert ở đây, không bao giờ UPDATE trực tiếp drivers.wallet_balance nữa — số dư luôn
-- là SUM(amount) theo driver_id+wallet (xem view driver_wallet_balances bên dưới).
CREATE TABLE driver_wallet_transactions (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id      UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  wallet         TEXT NOT NULL CHECK (wallet IN ('cod','earning')),
  entry_type     TEXT NOT NULL CHECK (entry_type IN (
                    'cod_collected', 'cod_settled',
                    'earning_released', 'buy_on_behalf_reimbursement',
                    'withdrawal', 'withdrawal_rejected', 'admin_adjustment'
                  )),
  amount         INTEGER NOT NULL CHECK (amount <> 0),  -- có dấu (+/-)
  order_id       UUID REFERENCES orders(id),
  delivery_id    UUID REFERENCES deliveries(id),
  settlement_id  UUID REFERENCES driver_cod_settlements(id),
  withdrawal_id  UUID REFERENCES driver_wallet_withdrawals(id),
  note           TEXT,
  created_by     UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT driver_wallet_tx_adjustment_needs_note CHECK (entry_type <> 'admin_adjustment' OR note IS NOT NULL)
);
COMMENT ON TABLE driver_wallet_transactions IS
  'Sổ cái ví tài xế — nguồn sự thật DUY NHẤT cho số dư (xem view driver_wallet_balances). Không bao giờ UPDATE drivers.wallet_balance trực tiếp, luôn insert 1 dòng ở đây kèm order_id/delivery_id/settlement_id/withdrawal_id liên quan để truy vết được, đặc biệt admin_adjustment bắt buộc phải có note (lý do).';

CREATE INDEX idx_driver_wallet_tx_driver ON driver_wallet_transactions (driver_id, wallet, created_at DESC);

CREATE VIEW driver_wallet_balances AS
  SELECT driver_id,
         COALESCE(SUM(amount) FILTER (WHERE wallet = 'cod'), 0)::INTEGER AS cod_balance,
         COALESCE(SUM(amount) FILTER (WHERE wallet = 'earning'), 0)::INTEGER AS earning_balance
    FROM driver_wallet_transactions
   GROUP BY driver_id;
COMMENT ON VIEW driver_wallet_balances IS
  'Số dư 2 ví hiện tại của từng tài xế, tính động từ driver_wallet_transactions — LEFT JOIN bảng này (COALESCE về 0 cho tài xế chưa có giao dịch nào) thay vì đọc drivers.wallet_balance.';

-- Cờ chống chạy trùng cho bước cộng tiền lúc giao xong — cùng cơ chế với deliveries.reimbursed_at
-- (migration 43) đã dùng cho tiền ứng mua hộ, vá lỗ hổng update_delivery_status() cũ cộng đúp
-- nếu bị gọi lại 'delivered' nhiều lần cho cùng 1 chuyến.
ALTER TABLE deliveries ADD COLUMN cod_credited_at TIMESTAMPTZ;
ALTER TABLE deliveries ADD COLUMN earning_credited_at TIMESTAMPTZ;
COMMENT ON COLUMN deliveries.cod_credited_at IS
  'Thời điểm đã insert dòng cod_collected vào driver_wallet_transactions (chỉ đơn COD) — chống cộng đúp nếu status delivered bị replay.';
COMMENT ON COLUMN deliveries.earning_credited_at IS
  'Thời điểm đã insert dòng earning_released vào driver_wallet_transactions (mọi payment_method) — chống cộng đúp nếu status delivered bị replay.';

-- update_delivery_status(): chữ ký giữ nguyên, thân hàm giữ nguyên phần còn lại y hệt
-- hofa-db/43_buy_on_behalf_driver_dispatch.sql, chỉ đổi 2 khối tiền (picked_up mua hộ + delivered)
-- từ UPDATE drivers.wallet_balance thô sang insert driver_wallet_transactions có cờ chống trùng.
CREATE OR REPLACE FUNCTION update_delivery_status(
  p_delivery_id UUID,
  p_new_status  delivery_status,
  p_otp         VARCHAR DEFAULT NULL,       -- bắt buộc khi picked_up (trừ đơn mua hộ) hoặc delivered
  p_recipient_name VARCHAR DEFAULT NULL,
  p_proof_photo_urls JSONB DEFAULT NULL,
  p_signature_url VARCHAR DEFAULT NULL,
  p_failure_reason TEXT DEFAULT NULL
) RETURNS deliveries AS $$
DECLARE
  v_delivery deliveries;
  v_item RECORD;
  v_merchant_type merchant_type;
  v_order_subtotal INTEGER;
  v_order_payment_method payment_method;
  v_order_total INTEGER;
  v_commission_rate NUMERIC;
BEGIN
  SELECT * INTO v_delivery FROM deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy chuyến giao hàng' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT m.merchant_type, o.subtotal INTO v_merchant_type, v_order_subtotal
    FROM orders o JOIN merchants m ON m.id = o.merchant_id
   WHERE o.id = v_delivery.order_id;

  -- Đơn mua hộ: tài xế tự đi mua, không có nhân viên cửa hàng nào đọc OTP lấy hàng cho tài xế
  -- — bỏ OTP ở bước này, bắt buộc ít nhất 1 ảnh hoá đơn/hàng đã mua làm bằng chứng thay thế.
  -- Đơn thường giữ nguyên yêu cầu OTP như trước.
  IF p_new_status = 'picked_up' THEN
    IF v_merchant_type = 'buy_on_behalf' THEN
      IF p_proof_photo_urls IS NULL OR jsonb_array_length(p_proof_photo_urls) = 0 THEN
        RAISE EXCEPTION 'Cần ít nhất 1 ảnh hoá đơn/hàng đã mua' USING ERRCODE = 'check_violation';
      END IF;
    ELSIF p_otp IS NULL OR p_otp <> v_delivery.pickup_otp THEN
      RAISE EXCEPTION 'Mã OTP lấy hàng không đúng' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF p_new_status = 'delivered' AND (p_otp IS NULL OR p_otp <> v_delivery.delivery_otp) THEN
    RAISE EXCEPTION 'Mã OTP giao hàng không đúng' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE deliveries SET
    status = p_new_status,
    accepted_at      = CASE WHEN p_new_status = 'accepted'      THEN now() ELSE accepted_at END,
    arrived_store_at = CASE WHEN p_new_status = 'arrived_store'  THEN now() ELSE arrived_store_at END,
    picked_up_at     = CASE WHEN p_new_status = 'picked_up'      THEN now() ELSE picked_up_at END,
    delivered_at     = CASE WHEN p_new_status = 'delivered'      THEN now() ELSE delivered_at END,
    recipient_name   = COALESCE(p_recipient_name, recipient_name),
    proof_photo_urls = COALESCE(p_proof_photo_urls, proof_photo_urls),
    signature_url    = COALESCE(p_signature_url, signature_url),
    failure_reason   = CASE WHEN p_new_status = 'failed' THEN p_failure_reason ELSE failure_reason END,
    attempt_count    = CASE WHEN p_new_status = 'failed' THEN attempt_count + 1 ELSE attempt_count END
  WHERE id = p_delivery_id
  RETURNING * INTO v_delivery;

  -- Lấy hàng xong: trừ tồn kho thật (on_hand) và bỏ phần đã giữ (reserved)
  IF p_new_status = 'picked_up' THEN
    FOR v_item IN
      SELECT oi.variant_id, oi.quantity FROM order_items oi
       JOIN orders o ON o.id = oi.order_id WHERE o.id = (
         SELECT order_id FROM deliveries WHERE id = p_delivery_id
       )
    LOOP
      IF v_item.variant_id IS NOT NULL THEN
        -- Thứ tự bắt buộc: nhả reserved TRƯỚC, trừ on_hand SAU. Nếu làm ngược lại,
        -- khi nhiều đơn khác cũng đang giữ chỗ cùng biến thể (reserved cộng dồn cao),
        -- bước trừ on_hand có thể tạm thời làm on_hand < reserved và vi phạm
        -- CHECK inventory_reserved_lte_hand ngay giữa chừng (constraint không hoãn được).
        PERFORM release_inventory(
          (SELECT branch_id FROM orders WHERE id = v_delivery.order_id),
          v_item.variant_id, v_item.quantity
        );
        PERFORM apply_stock_movement(
          (SELECT branch_id FROM orders WHERE id = v_delivery.order_id),
          v_item.variant_id, 'sale_out', -v_item.quantity, 'order', v_delivery.order_id
        );
      END IF;
    END LOOP;
    PERFORM update_order_status(v_delivery.order_id, 'picked_up', NULL, 'driver', NULL, TRUE);

    -- Mua hộ: hoàn ngay tiền hàng tài xế vừa ứng ra mua — tách biệt phí giao hàng (vẫn cộng
    -- lúc giao xong như bình thường ở nhánh 'delivered' bên dưới). Chặn cộng 2 lần bằng
    -- reimbursed_at (v_delivery ở đây là bản TRƯỚC UPDATE reimbursed_at nên vẫn đọc đúng). Tiền
    -- hoàn là VỐN tài xế tự bỏ ra, không phải thu nhập/COD nợ HOFA nên ghi vào ví thu nhập
    -- (rút được ngay), khác entry_type với earning_released để phân biệt lúc xem lịch sử.
    IF v_merchant_type = 'buy_on_behalf' AND v_delivery.reimbursed_at IS NULL THEN
      INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, delivery_id)
      VALUES (v_delivery.driver_id, 'earning', 'buy_on_behalf_reimbursement', COALESCE(v_order_subtotal, 0), p_delivery_id);
      UPDATE deliveries SET reimbursed_at = now() WHERE id = p_delivery_id;
    END IF;
  ELSIF p_new_status = 'delivering' THEN
    PERFORM update_order_status(v_delivery.order_id, 'delivering', NULL, 'driver', NULL, TRUE);
  ELSIF p_new_status = 'delivered' THEN
    PERFORM update_order_status(v_delivery.order_id, 'delivered', NULL, 'driver', NULL, TRUE);
    UPDATE drivers SET status = 'online', total_deliveries = total_deliveries + 1
     WHERE id = v_delivery.driver_id;

    -- Cộng ví: COD (nếu có) vào ví COD (số tiền khách trả tài xế, còn phải nộp lại HOFA) +
    -- phí giao vào ví thu nhập cho MỌI phương thức thanh toán (trước đây chỉ COD mới được trả
    -- driver_fee — lỗ hổng đã vá). Guard earning_credited_at chống chạy trùng.
    IF v_delivery.earning_credited_at IS NULL THEN
      SELECT payment_method, total_amount INTO v_order_payment_method, v_order_total
        FROM orders WHERE id = v_delivery.order_id;
      SELECT driver_fee_commission_rate INTO v_commission_rate
        FROM driver_finance_settings ORDER BY updated_at DESC LIMIT 1;
      v_commission_rate := COALESCE(v_commission_rate, 0);

      IF v_order_payment_method = 'cod' THEN
        INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, order_id)
        VALUES (v_delivery.driver_id, 'cod', 'cod_collected', v_order_total, v_delivery.order_id);
      END IF;

      INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, delivery_id)
      VALUES (
        v_delivery.driver_id, 'earning', 'earning_released',
        v_delivery.driver_fee - ROUND(v_delivery.driver_fee * v_commission_rate / 100.0),
        p_delivery_id
      );

      UPDATE deliveries SET cod_credited_at = now(), earning_credited_at = now() WHERE id = p_delivery_id;
    END IF;
  ELSIF p_new_status = 'failed' THEN
    UPDATE drivers SET status = 'online' WHERE id = v_delivery.driver_id;
  END IF;

  RETURN v_delivery;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION update_delivery_status IS
  'Đổi trạng thái chuyến giao, kiểm OTP (trừ picked_up của đơn mua hộ — dùng ảnh thay OTP), đồng bộ trạng thái đơn, trừ kho thật lúc lấy hàng, cộng ví tài xế (2 ví, qua driver_wallet_transactions) lúc giao xong và lúc mua xong nếu là đơn mua hộ — xem hofa-db/62_driver_wallet_ledger.sql.';

-- Rút tiền: kiểm tra số dư + hạn mức COD và insert yêu cầu + dòng sổ cái trong CÙNG 1 transaction
-- (atomic) — khoá hàng drivers trước (FOR UPDATE) để 2 yêu cầu rút song song của cùng 1 tài xế
-- không cùng vượt số dư thật (server JS không có transaction đa câu lệnh, mọi bất biến tài
-- chính phải nằm trong RPC, đúng pattern update_delivery_status/create_order đã dùng).
CREATE OR REPLACE FUNCTION request_driver_withdrawal(p_driver_id UUID, p_amount INTEGER)
RETURNS driver_wallet_withdrawals AS $$
DECLARE
  v_earning_balance INTEGER;
  v_cod_balance INTEGER;
  v_cod_limit INTEGER;
  v_min_balance INTEGER;
  v_withdrawal driver_wallet_withdrawals;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Số tiền rút không hợp lệ' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM 1 FROM drivers WHERE id = p_driver_id FOR UPDATE;

  SELECT COALESCE(SUM(amount) FILTER (WHERE wallet = 'earning'), 0),
         COALESCE(SUM(amount) FILTER (WHERE wallet = 'cod'), 0)
    INTO v_earning_balance, v_cod_balance
    FROM driver_wallet_transactions WHERE driver_id = p_driver_id;

  SELECT cod_debt_limit INTO v_cod_limit FROM driver_finance_settings ORDER BY updated_at DESC LIMIT 1;
  v_cod_limit := COALESCE(v_cod_limit, 2000000);
  -- min_withdrawal_balance (hofa-db/47_driver_wallet_deposits_withdrawals.sql) — số dư tối
  -- thiểu admin muốn tài xế luôn còn lại trong ví thu nhập sau khi rút, giữ nguyên ý nghĩa cũ
  -- dù đã tách ví, không bỏ mất cấu hình admin đã đặt.
  SELECT min_withdrawal_balance INTO v_min_balance FROM bank_account_settings ORDER BY updated_at DESC LIMIT 1;
  v_min_balance := COALESCE(v_min_balance, 0);

  IF v_cod_balance > v_cod_limit THEN
    RAISE EXCEPTION 'Đang giữ COD vượt hạn mức (%đ) — nộp lại COD trước khi rút tiền', v_cod_limit
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_earning_balance - p_amount < v_min_balance THEN
    RAISE EXCEPTION 'Số dư ví thu nhập không đủ để rút số tiền này' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO driver_wallet_withdrawals (driver_id, amount) VALUES (p_driver_id, p_amount)
    RETURNING * INTO v_withdrawal;
  INSERT INTO driver_wallet_transactions (driver_id, wallet, entry_type, amount, withdrawal_id)
    VALUES (p_driver_id, 'earning', 'withdrawal', -p_amount, v_withdrawal.id);

  RETURN v_withdrawal;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION request_driver_withdrawal IS
  'Kiểm earning_balance đủ + cod_balance chưa vượt hạn mức, rồi tạo yêu cầu rút + dòng sổ cái entry_type=withdrawal trong 1 transaction — xem GET /drivers/me/wallet (server).';

-- Nộp COD theo lô — chỉ nhận đúng đơn COD đã giao, thuộc tài xế này, CHƯA nằm trong lần nộp nào
-- đang pending/confirmed (tránh nộp trùng 1 đơn 2 lần). Tự tính total_amount từ orders, không
-- tin số tài xế gửi lên.
CREATE OR REPLACE FUNCTION submit_driver_cod_settlement(
  p_driver_id UUID, p_order_ids UUID[], p_proof_image_url TEXT DEFAULT NULL
) RETURNS driver_cod_settlements AS $$
DECLARE
  v_settlement driver_cod_settlements;
  v_total INTEGER;
BEGIN
  IF p_order_ids IS NULL OR array_length(p_order_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Chưa chọn đơn nào để nộp COD' USING ERRCODE = 'check_violation';
  END IF;

  SELECT COALESCE(SUM(o.total_amount), 0) INTO v_total
    FROM orders o JOIN deliveries d ON d.order_id = o.id
   WHERE o.id = ANY(p_order_ids) AND d.driver_id = p_driver_id
     AND o.payment_method = 'cod' AND o.status IN ('delivered','completed')
     AND NOT EXISTS (
       SELECT 1 FROM driver_cod_settlement_items i
         JOIN driver_cod_settlements s ON s.id = i.settlement_id
        WHERE i.order_id = o.id AND s.status IN ('pending','confirmed')
     );

  IF v_total = 0 THEN
    RAISE EXCEPTION 'Không có đơn COD hợp lệ nào để nộp (đã nộp trước đó hoặc không thuộc về bạn)'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO driver_cod_settlements (driver_id, total_amount, proof_image_url)
    VALUES (p_driver_id, v_total, p_proof_image_url) RETURNING * INTO v_settlement;

  INSERT INTO driver_cod_settlement_items (settlement_id, order_id, amount)
  SELECT v_settlement.id, o.id, o.total_amount
    FROM orders o JOIN deliveries d ON d.order_id = o.id
   WHERE o.id = ANY(p_order_ids) AND d.driver_id = p_driver_id
     AND o.payment_method = 'cod' AND o.status IN ('delivered','completed')
     AND NOT EXISTS (
       SELECT 1 FROM driver_cod_settlement_items i
         JOIN driver_cod_settlements s ON s.id = i.settlement_id
        WHERE i.order_id = o.id AND s.status IN ('pending','confirmed') AND s.id <> v_settlement.id
     );

  RETURN v_settlement;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION submit_driver_cod_settlement IS
  'Tạo 1 lần nộp COD gồm nhiều đơn — tự lọc đúng đơn COD đã giao, thuộc tài xế, chưa nộp lần nào khác đang pending/confirmed, tự tính total_amount từ orders.total_amount.';

COMMIT;
