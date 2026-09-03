-- ============================================================================
-- MIGRATION 103 — SĐT hỗ trợ nạp tiền (app tài xế bỏ QR chuyển khoản trong app, chuyển qua
-- liên hệ SĐT/SMS/Zalo)
--
-- App tài xế không còn hiện mã VietQR ngay trong app lúc bấm "Nạp tiền" — thay bằng mở gọi/nhắn
-- tin tới SĐT hỗ trợ của sàn (xem hofa_driver_app/lib/screens/earnings/earnings_screen.dart).
-- Tận dụng lại bảng bank_account_settings (đã có sẵn, chỉ 1 dòng đang áp dụng) thay vì tạo bảng
-- mới, vì đây cùng là thông tin liên hệ nạp tiền của sàn.
-- ============================================================================

ALTER TABLE bank_account_settings
  ADD COLUMN IF NOT EXISTS support_phone TEXT;

COMMENT ON COLUMN bank_account_settings.support_phone IS
  'SĐT hỗ trợ nạp tiền — app tài xế dùng để mở gọi/SMS/Zalo khi tài xế bấm "Nạp tiền", thay cho hiện QR chuyển khoản trực tiếp trong app.';
