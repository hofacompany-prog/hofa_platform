/// Cấu hình OTP toàn sàn (admin cấu hình, đọc public kể cả trước khi đăng nhập): ngưỡng giá
/// trị đơn để bắt buộc xác nhận OTP giao hàng (đơn <= ngưỡng bỏ qua OTP hoàn toàn, xem
/// hofa-db/73_otp_threshold_settings.sql) và có bắt nhập mã OTP lúc đăng ký hay bỏ qua thẳng
/// (xem hofa-db/76_registration_otp_toggle.sql).
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
