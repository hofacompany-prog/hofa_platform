-- Cho phép tạo voucher "công khai" (hiện thành danh sách để khách chọn/bấm áp dụng,
-- kiểu Shopee) bên cạnh voucher hiện có (khách phải tự gõ đúng mã mới dùng được).
BEGIN;

ALTER TABLE vouchers ADD COLUMN is_public BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN vouchers.is_public IS
  'true = hiện trong danh sách cho khách chọn (không cần gõ mã); false = chỉ dùng được
  khi khách tự nhập đúng mã';

COMMIT;
