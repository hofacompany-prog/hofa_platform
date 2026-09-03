-- ============================================================================
-- MIGRATION 104 — Cho phép admin từ chối yêu cầu nạp tiền của tài xế
--
-- driver_wallet_deposits trước đây chỉ có 2 trạng thái (pending/confirmed) — không có cách từ
-- chối yêu cầu sai/không chuyển khoản (vd tài xế bấm nhầm số tiền, hoặc không bao giờ chuyển
-- khoản thật). Thêm 'rejected' + reject_reason, cùng kiểu với driver_wallet_withdrawals đã có
-- sẵn (hofa-db/47_driver_wallet_deposits_withdrawals.sql). Khác withdrawals: deposit KHÔNG trừ
-- tiền lúc tạo (chỉ cộng lúc confirm), nên từ chối không cần hoàn tiền gì — chỉ đánh dấu để yêu
-- cầu biến mất khỏi hàng chờ xử lý.
-- ============================================================================

ALTER TABLE driver_wallet_deposits DROP CONSTRAINT IF EXISTS driver_wallet_deposits_status_check;
ALTER TABLE driver_wallet_deposits ADD CONSTRAINT driver_wallet_deposits_status_check
  CHECK (status IN ('pending', 'confirmed', 'rejected'));

ALTER TABLE driver_wallet_deposits
  ADD COLUMN IF NOT EXISTS reject_reason TEXT;
