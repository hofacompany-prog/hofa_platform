/// Cấu hình quét tìm tài xế khi đơn chưa có ai nhận — xem
/// server/src/dispatch.js#sweepDriverSearch. Riêng biệt với DriverAcceptSettings (thời gian
/// thanh trượt "Nhận đơn" SAU KHI đã gán được 1 tài xế cụ thể) — cái này là TRƯỚC khi gán
/// được, lúc quét mà chưa tìm thấy ai cả.
class DriverDispatchSettings {
  final String? id;
  final int rescanIntervalSeconds;
  final int maxRescanAttempts;

  DriverDispatchSettings({
    this.id,
    required this.rescanIntervalSeconds,
    required this.maxRescanAttempts,
  });

  factory DriverDispatchSettings.fromJson(Map<String, dynamic> json) =>
      DriverDispatchSettings(
        id: json['id'] as String?,
        rescanIntervalSeconds:
            (json['rescan_interval_seconds'] as num?)?.toInt() ?? 60,
        maxRescanAttempts: (json['max_rescan_attempts'] as num?)?.toInt() ?? 10,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory DriverDispatchSettings.fallback() =>
      DriverDispatchSettings(rescanIntervalSeconds: 60, maxRescanAttempts: 10);

  Map<String, dynamic> toJson() => {
    'rescan_interval_seconds': rescanIntervalSeconds,
    'max_rescan_attempts': maxRescanAttempts,
  };
}
