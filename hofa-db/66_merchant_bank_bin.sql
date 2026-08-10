-- ============================================================================
-- MIGRATION 66 — Thêm merchants.bank_bin, mirror drivers.bank_bin (46_driver_bank_and_
-- verification.sql) để cửa hàng chọn ngân hàng qua dropdown (bảng banks có sẵn, 48_seed_banks.
-- sql) thay vì gõ tay tên ngân hàng — dọn đường cho VietQR lúc admin duyệt rút tiền cửa hàng
-- sau này (xem hofa-db/65_merchant_wallet_withdrawals.sql, hiện admin đang chuyển khoản tay).
-- ============================================================================

ALTER TABLE merchants ADD COLUMN bank_bin TEXT;
COMMENT ON COLUMN merchants.bank_bin IS
  'Mã BIN ngân hàng (theo bảng banks) — chọn qua dropdown ở màn tạo/sửa cửa hàng, dùng để tạo VietQR sau này. NULL với cửa hàng đã có bank_name từ trước khi có dropdown (migration 66), tự khớp lại khi cửa hàng vào sửa hồ sơ lần tới.';
