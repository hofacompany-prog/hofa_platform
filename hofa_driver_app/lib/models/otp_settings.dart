/// Ngưỡng giá trị đơn tối thiểu để BẮT BUỘC xác nhận OTP (cửa hàng-tài xế lúc lấy hàng, tài
/// xế-khách lúc giao hàng) — admin cấu hình toàn sàn, xem hofa-db/73_otp_threshold_settings.sql.
/// Đơn giá trị THẤP HƠN HOẶC BẰNG ngưỡng này bỏ qua xác nhận OTP hoàn toàn.
class OtpSettings {
  final int minOrderAmount;

  OtpSettings({required this.minOrderAmount});

  factory OtpSettings.fromJson(Map<String, dynamic> json) => OtpSettings(
    minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
  );

  factory OtpSettings.fallback() => OtpSettings(minOrderAmount: 0);
}
