-- Thông tin tài khoản ngân hàng của sàn — dùng tạo mã VietQR cho khách quét chuyển khoản khi
-- đặt hàng bank_transfer (xem GET/PATCH /bank-account-settings). Chỉ giữ 1 dòng đang áp dụng
-- (dòng mới nhất theo updated_at), cùng kiểu với driver_accept_settings/auto_accept_settings.
-- Admin tự nhập bank_bin (mã ngân hàng chuẩn VietQR/Napas, vd Vietcombank = 970436) thay vì
-- chọn từ danh sách dựng sẵn trong code — tránh cứng mã sai/lỗi thời, admin tự tra tại
-- vietqr.io/danh-sach-ngan-hang.
CREATE TABLE IF NOT EXISTS bank_account_settings (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  bank_name            TEXT,
  bank_bin             TEXT,
  account_number       TEXT,
  account_holder_name  TEXT,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by           UUID REFERENCES users(id) ON DELETE SET NULL
);
COMMENT ON TABLE bank_account_settings IS
  'Thông tin tài khoản ngân hàng của sàn — dùng tạo VietQR cho khách chuyển khoản khi đặt hàng. Chỉ 1 dòng đang áp dụng.';
COMMENT ON COLUMN bank_account_settings.bank_bin IS
  'Mã BIN ngân hàng theo chuẩn VietQR (tra tại vietqr.io/danh-sach-ngan-hang) — bắt buộc để tạo được QR, để trống thì app khách hiện hướng dẫn liên hệ hỗ trợ thay vì QR.';

INSERT INTO bank_account_settings (bank_name)
SELECT NULL WHERE NOT EXISTS (SELECT 1 FROM bank_account_settings);
