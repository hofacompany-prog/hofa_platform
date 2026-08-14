-- ============================================================================
-- MIGRATION 76 — Bật/tắt bước nhập mã OTP lúc ĐĂNG KÝ (khách hàng/cửa hàng/tài xế), admin cấu
-- hình qua GET/PATCH /otp-settings (route + bảng otp_settings đã có từ
-- hofa-db/73_otp_threshold_settings.sql — đây là ngưỡng OTP GIAO HÀNG, khác khái niệm, dùng
-- chung 1 bảng cho gọn vì cùng là "cấu hình OTP toàn sàn", cả 2 app đều đọc public trước khi
-- đăng nhập). Mặc định FALSE = giữ đúng hành vi đang chạy (đăng ký bỏ qua thẳng bước nhập mã,
-- xem kOtpStepEnabled cũ trong core/phone_auth.dart của 3 app) cho tới khi admin chủ động bật.
-- ============================================================================

ALTER TABLE otp_settings
  ADD COLUMN registration_otp_enabled BOOLEAN NOT NULL DEFAULT false;

COMMENT ON TABLE otp_settings IS
  'Cấu hình OTP toàn sàn, admin sửa qua GET/PATCH /otp-settings, đọc public (kể cả trước khi đăng nhập): min_order_amount = ngưỡng giá trị đơn để bắt buộc OTP lấy hàng/giao hàng (hofa-db/73_otp_threshold_settings.sql); registration_otp_enabled = có bắt nhập mã OTP lúc đăng ký hay bỏ qua thẳng (hofa-db/76_registration_otp_toggle.sql). Chỉ giữ 1 dòng (mới nhất theo updated_at) đang áp dụng.';

COMMENT ON COLUMN otp_settings.registration_otp_enabled IS
  'TRUE = bắt nhập mã OTP lúc đăng ký (app khách/cửa hàng/tài xế). FALSE = bỏ qua thẳng bước này, tạo tài khoản luôn.';
