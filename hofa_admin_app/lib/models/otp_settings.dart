/// Cấu hình OTP toàn sàn: ngưỡng giá trị đơn (VNĐ) để bắt buộc xác nhận OTP lấy hàng
/// (cửa hàng-tài xế) và giao hàng (tài xế-khách) — đơn <= ngưỡng bỏ qua OTP hoàn toàn; và có
/// bắt nhập mã OTP lúc đăng ký hay bỏ qua thẳng — xem hofa-db/73_otp_threshold_settings.sql,
/// hofa-db/76_registration_otp_toggle.sql.
class OtpSettings {
  final String? id;
  final int minOrderAmount;
  final bool registrationOtpEnabled;

  OtpSettings({
    this.id,
    required this.minOrderAmount,
    required this.registrationOtpEnabled,
  });

  factory OtpSettings.fromJson(Map<String, dynamic> json) => OtpSettings(
    id: json['id'] as String?,
    minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
    registrationOtpEnabled: json['registration_otp_enabled'] as bool? ?? false,
  );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory OtpSettings.fallback() =>
      OtpSettings(minOrderAmount: 0, registrationOtpEnabled: false);

  Map<String, dynamic> toJson() => {
    'min_order_amount': minOrderAmount,
    'registration_otp_enabled': registrationOtpEnabled,
  };
}
