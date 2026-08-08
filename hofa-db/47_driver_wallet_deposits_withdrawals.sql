-- Tài xế tự nạp/rút ví (drivers.wallet_balance) — admin duyệt tay từng yêu cầu ở tab Thanh toán,
-- cùng tinh thần với bank_account_settings/xác nhận thanh toán đơn hàng (session trước).
CREATE TABLE IF NOT EXISTS driver_wallet_deposits (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id    UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  amount       INTEGER NOT NULL CHECK (amount > 0),
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at TIMESTAMPTZ,
  confirmed_by UUID REFERENCES users(id) ON DELETE SET NULL
);
COMMENT ON TABLE driver_wallet_deposits IS
  'Yêu cầu nạp tiền vào ví tài xế — tài xế chuyển khoản theo QR (tài khoản ngân hàng của sàn, bank_account_settings), admin xác nhận đã nhận tiền thì mới cộng wallet_balance.';

CREATE TABLE IF NOT EXISTS driver_wallet_withdrawals (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id     UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  amount        INTEGER NOT NULL CHECK (amount > 0),
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed','rejected')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at  TIMESTAMPTZ,
  confirmed_by  UUID REFERENCES users(id) ON DELETE SET NULL,
  reject_reason TEXT
);
COMMENT ON TABLE driver_wallet_withdrawals IS
  'amount đã bị trừ khỏi drivers.wallet_balance NGAY lúc tạo dòng (POST /drivers/me/wallet/withdrawals) để tránh tài xế tạo nhiều yêu cầu vượt số dư thật trước khi admin duyệt. Admin xác nhận đã chuyển khoản thì chỉ đánh dấu xong (tiền đã trừ từ trước); admin từ chối thì hoàn lại đúng amount vào wallet_balance.';

ALTER TABLE bank_account_settings ADD COLUMN min_withdrawal_balance INTEGER NOT NULL DEFAULT 0;
COMMENT ON COLUMN bank_account_settings.min_withdrawal_balance IS
  'Số dư tối thiểu phải còn lại trong ví tài xế sau khi rút — chặn rút cạn ví xuống âm/quá thấp.';
