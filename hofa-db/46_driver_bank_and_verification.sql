-- Danh sách ngân hàng (tên + mã BIN chuẩn VietQR) admin tự quản lý ở web admin (tab Thanh toán
-- > Ngân hàng) — tài xế chọn từ đây lúc đăng ký/sửa hồ sơ thay vì gõ tay, tránh sai/lệch chuẩn.
CREATE TABLE IF NOT EXISTS banks (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       TEXT NOT NULL,
  bin        TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE banks IS
  'Danh sách ngân hàng (tên + mã BIN chuẩn VietQR) admin tự quản lý — tài xế chọn từ đây lúc đăng ký/sửa hồ sơ.';

-- Thông tin ngân hàng của tài xế (nhận tiền lúc rút ví) + trạng thái hồ sơ bị từ chối. Tách
-- riêng rejected_at/rejection_reason khỏi verified_at hiện có vì verified_at NULL trước giờ chỉ
-- biểu diễn được 1 trạng thái "chưa duyệt" — giờ cần phân biệt "chưa từng xét" và "đã bị từ chối,
-- đang chờ tài xế sửa lại".
ALTER TABLE drivers
  ADD COLUMN bank_name             TEXT,
  ADD COLUMN bank_bin              TEXT,
  ADD COLUMN bank_account_number   TEXT,
  ADD COLUMN bank_account_holder   TEXT,
  ADD COLUMN rejected_at           TIMESTAMPTZ,
  ADD COLUMN rejection_reason      TEXT;
COMMENT ON COLUMN drivers.bank_bin IS
  'Mã BIN ngân hàng của tài xế — dùng tạo QR cho admin chuyển khoản khi tài xế rút ví.';
COMMENT ON COLUMN drivers.rejected_at IS
  'Thời điểm admin từ chối hồ sơ — NULL nghĩa là chưa từng bị từ chối HOẶC tài xế đã sửa/nộp lại hồ sơ (PATCH /drivers/me tự xoá cột này). verified_at luôn ưu tiên hơn nếu cả 2 khác NULL (không xảy ra trong luồng bình thường).';
