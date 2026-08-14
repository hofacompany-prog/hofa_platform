/// Ngưỡng giá trị đơn (VNĐ) để bắt buộc xác nhận OTP lấy hàng (cửa hàng-tài xế) và giao hàng
/// (tài xế-khách) — đơn <= ngưỡng bỏ qua OTP hoàn toàn, xem hofa-db/73_otp_threshold_settings.sql.
class OtpSettings {
  final String? id;
  final int minOrderAmount;

  OtpSettings({this.id, required this.minOrderAmount});

  factory OtpSettings.fromJson(Map<String, dynamic> json) => OtpSettings(
    id: json['id'] as String?,
    minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
  );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory OtpSettings.fallback() => OtpSettings(minOrderAmount: 0);

  Map<String, dynamic> toJson() => {'min_order_amount': minOrderAmount};
}
