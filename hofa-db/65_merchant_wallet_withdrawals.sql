-- ============================================================================
-- MIGRATION 65 — Rút tiền cho cửa hàng, đầy đủ như tài xế (yêu cầu → admin xác nhận đã chuyển
-- khoản) — mirror hofa-db/47_driver_wallet_deposits_withdrawals.sql +
-- request_driver_withdrawal (62_driver_wallet_ledger.sql), áp cho merchant_wallet_transactions
-- (64_merchant_wallet_ledger.sql) thay vì driver_wallet_transactions.
--
-- Khác driver: không có khái niệm "hạn mức COD" (cửa hàng không giữ tiền mặt hộ khách) nên rút
-- chỉ cần kiểm đủ số dư — không có bank_bin/QR cho cửa hàng (merchants chỉ có
-- bank_name/bank_account_no/bank_account_name dạng chữ, chưa từng thu thập mã BIN ngân hàng),
-- admin tự chuyển khoản tay bằng thông tin hiện ra, không dựng QR như bên tài xế.
-- ============================================================================

BEGIN;

CREATE TABLE merchant_wallet_withdrawals (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id   UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  amount        INTEGER NOT NULL CHECK (amount > 0),
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed','rejected')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at  TIMESTAMPTZ,
  confirmed_by  UUID REFERENCES users(id) ON DELETE SET NULL,
  reject_reason TEXT
);
COMMENT ON TABLE merchant_wallet_withdrawals IS
  'amount đã bị trừ khỏi merchant_wallet_balances NGAY lúc tạo dòng (RPC request_merchant_withdrawal) để tránh cửa hàng tạo nhiều yêu cầu vượt số dư thật trước khi admin duyệt. Admin xác nhận đã chuyển khoản thì chỉ đánh dấu xong; admin từ chối thì hoàn lại đúng amount (entry_type=withdrawal_rejected).';

ALTER TABLE merchant_wallet_transactions ADD COLUMN withdrawal_id UUID REFERENCES merchant_wallet_withdrawals(id);

ALTER TABLE merchant_wallet_transactions DROP CONSTRAINT merchant_wallet_transactions_entry_type_check;
ALTER TABLE merchant_wallet_transactions ADD CONSTRAINT merchant_wallet_transactions_entry_type_check
  CHECK (entry_type IN ('order_payout', 'withdrawal', 'withdrawal_rejected', 'admin_adjustment'));
ALTER TABLE merchant_wallet_transactions ADD CONSTRAINT merchant_wallet_tx_adjustment_needs_note
  CHECK (entry_type <> 'admin_adjustment' OR note IS NOT NULL);
COMMENT ON COLUMN merchant_wallet_transactions.entry_type IS
  'order_payout = tiền đơn giao xong (tự động); withdrawal/withdrawal_rejected = rút tiền + hoàn khi admin từ chối; admin_adjustment = admin cộng/trừ tay, bắt buộc note (lý do).';

-- Rút tiền: kiểm số dư + insert yêu cầu + dòng sổ cái trong CÙNG 1 transaction (atomic) — khoá
-- hàng merchants trước (FOR UPDATE) để 2 yêu cầu rút song song của cùng 1 cửa hàng không cùng
-- vượt số dư thật, đúng pattern request_driver_withdrawal đã dùng.
CREATE OR REPLACE FUNCTION request_merchant_withdrawal(p_merchant_id UUID, p_amount INTEGER)
RETURNS merchant_wallet_withdrawals AS $$
DECLARE
  v_balance INTEGER;
  v_withdrawal merchant_wallet_withdrawals;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Số tiền rút không hợp lệ' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM 1 FROM merchants WHERE id = p_merchant_id FOR UPDATE;

  SELECT COALESCE(SUM(amount), 0) INTO v_balance
    FROM merchant_wallet_transactions WHERE merchant_id = p_merchant_id;

  IF p_amount > v_balance THEN
    RAISE EXCEPTION 'Số dư không đủ để rút số tiền này' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO merchant_wallet_withdrawals (merchant_id, amount) VALUES (p_merchant_id, p_amount)
    RETURNING * INTO v_withdrawal;
  INSERT INTO merchant_wallet_transactions (merchant_id, entry_type, amount, withdrawal_id)
    VALUES (p_merchant_id, 'withdrawal', -p_amount, v_withdrawal.id);

  RETURN v_withdrawal;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION request_merchant_withdrawal IS
  'Kiểm số dư đủ rồi tạo yêu cầu rút + dòng sổ cái entry_type=withdrawal trong 1 transaction — xem POST /merchants/:id/wallet/withdrawals (server).';

COMMIT;
