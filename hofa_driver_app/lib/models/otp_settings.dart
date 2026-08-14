/// Cấu hình OTP toàn sàn (admin cấu hình, đọc public kể cả trước khi đăng nhập): ngưỡng giá
/// trị đơn tối thiểu để BẮT BUỘC xác nhận OTP (cửa hàng-tài xế lúc lấy hàng, tài xế-khách lúc
/// giao hàng) — đơn THẤP HƠN HOẶC BẰNG ngưỡng bỏ qua OTP hoàn toàn, xem
/// hofa-db/73_otp_threshold_settings.sql; và có bắt nhập mã OTP lúc đăng ký hay bỏ qua thẳng,
/// xem hofa-db/76_registration_otp_toggle.sql.
class OtpSettings {
  final int minOrderAmount;
  final bool registrationOtpEnabled;

  OtpSettings({
    required this.minOrderAmount,
    required this.registrationOtpEnabled,
  });

  factory OtpSettings.fromJson(Map<String, dynamic> json) => OtpSettings(
    minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
    registrationOtpEnabled: json['registration_otp_enabled'] as bool? ?? false,
  );

  factory OtpSettings.fallback() =>
      OtpSettings(minOrderAmount: 0, registrationOtpEnabled: false);
}
