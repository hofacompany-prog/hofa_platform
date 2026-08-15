-- ============================================================================
-- MIGRATION 86 — driver_finance_settings.min_withdrawal_amount: admin đặt số tiền tối thiểu
-- 1 lần rút tiền của tài xế, chặn rút vặt (vd 1-2đ) làm phình danh sách yêu cầu chờ duyệt.
-- Khác hẳn bank_account_settings.min_withdrawal_balance đã có sẵn (hofa-db/47_driver_wallet_
-- deposits_withdrawals.sql) — cột đó là số dư TỐI THIỂU CÒN LẠI sau khi rút, cột mới này là
-- số tiền TỐI THIỂU CỦA CHÍNH LẦN RÚT ĐÓ. Cả 2 điều kiện cùng áp dụng độc lập.
-- ============================================================================

ALTER TABLE driver_finance_settings
  ADD COLUMN min_withdrawal_amount INTEGER NOT NULL DEFAULT 0
  CONSTRAINT driver_finance_min_withdrawal_valid CHECK (min_withdrawal_amount >= 0);
COMMENT ON COLUMN driver_finance_settings.min_withdrawal_amount IS
  'Số tiền tối thiểu cho 1 lần rút tiền của tài xế (VNĐ) — 0 = không giới hạn. Chặn ở
  request_driver_withdrawal(), xem hofa-db/86_driver_min_withdrawal_amount.sql.';

-- request_driver_withdrawal(): chữ ký + thân hàm y hệt hofa-db/69_driver_wallet_vi_tren.sql,
-- chỉ THÊM 1 điều kiện kiểm min_withdrawal_amount ngay sau điều kiện amount > 0 hiện có.
CREATE OR REPLACE FUNCTION request_driver_withdrawal(p_driver_id UUID, p_amount INTEGER)
RETURNS driver_wallet_withdrawals AS $$
DECLARE
  v_earning_balance INTEGER;
  v_min_balance INTEGER;
  v_min_amount INTEGER;
  v_withdrawal driver_wallet_withdrawals;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Số tiền rút không hợp lệ' USING ERRCODE = 'check_violation';
  END IF;

  SELECT min_withdrawal_amount INTO v_min_amount FROM driver_finance_settings ORDER BY updated_at DESC LIMIT 1;
  v_min_amount := COALESCE(v_min_amount, 0);
  IF p_amount < v_min_amount THEN
    RAISE EXCEPTION 'Số tiền rút tối thiểu là % đ', v_min_amount USING ERRCODE = 'check_violation';
  END IF;

  PERFORM 1 FROM drivers WHERE id = p_driver_id FOR UPDATE;

  SELECT COALESCE(SUM(amount) FILTER (WHERE wallet = 'earning'), 0)
    INTO v_earning_balance
    FROM driver_wallet_transactions WHERE driver_id = p_driver_id;

  SELECT min_withdrawal_balance INTO v_min_balance FROM bank_account_settings ORDER BY updated_at DESC LIMIT 1;
  v_min_balance := COALESCE(v_min_balance, 0);

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
  'Kiểm số tiền rút >= min_withdrawal_amount, earning_balance đủ, rồi tạo yêu cầu rút + dòng sổ cái entry_type=withdrawal trong 1 transaction — xem POST /drivers/me/wallet/withdrawals (server). Xem hofa-db/86_driver_min_withdrawal_amount.sql.';
