/// Chu kỳ (phút) app Khách nhắc lại popup cài PWA cho khách chưa cài — xem
/// hofa-db/88_pwa_reminder_settings.sql.
class PwaReminderSettings {
  final String? id;
  final int intervalMinutes;

  PwaReminderSettings({this.id, required this.intervalMinutes});

  factory PwaReminderSettings.fromJson(Map<String, dynamic> json) =>
      PwaReminderSettings(
        id: json['id'] as String?,
        intervalMinutes: (json['interval_minutes'] as num?)?.toInt() ?? 5,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration/lưu lần nào).
  factory PwaReminderSettings.fallback() =>
      PwaReminderSettings(intervalMinutes: 5);

  Map<String, dynamic> toJson() => {'interval_minutes': intervalMinutes};
}
