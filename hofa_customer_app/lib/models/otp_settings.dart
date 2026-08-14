/// Ngưỡng giá trị đơn (VNĐ) để bắt buộc xác nhận OTP giao hàng (tài xế-khách) — đơn <= ngưỡng
/// bỏ qua OTP hoàn toàn, xem hofa-db/73_otp_threshold_settings.sql.
class OtpSettings {
  final int minOrderAmount;

  OtpSettings({required this.minOrderAmount});

  factory OtpSettings.fromJson(Map<String, dynamic> json) => OtpSettings(
    minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
  );

  factory OtpSettings.fallback() => OtpSettings(minOrderAmount: 0);
}
