/// Tham số toàn sàn cho thanh trượt "Nhận đơn" của tài xế (driver app) — riêng biệt với
/// AutoAcceptSettings (cửa hàng), không dùng chung bảng/route.
class DriverAcceptSettings {
  final String? id;
  final int autoAcceptSweepSeconds;
  final int manualAcceptSweepSeconds;

  DriverAcceptSettings({
    this.id,
    required this.autoAcceptSweepSeconds,
    required this.manualAcceptSweepSeconds,
  });

  factory DriverAcceptSettings.fromJson(Map<String, dynamic> json) => DriverAcceptSettings(
        id: json['id'] as String?,
        autoAcceptSweepSeconds: (json['auto_accept_sweep_seconds'] as num?)?.toInt() ?? 8,
        manualAcceptSweepSeconds: (json['manual_accept_sweep_seconds'] as num?)?.toInt() ?? 25,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory DriverAcceptSettings.fallback() => DriverAcceptSettings(
        autoAcceptSweepSeconds: 8,
        manualAcceptSweepSeconds: 25,
      );

  Map<String, dynamic> toJson() => {
        'auto_accept_sweep_seconds': autoAcceptSweepSeconds,
        'manual_accept_sweep_seconds': manualAcceptSweepSeconds,
      };
}
