/// Cấu hình chung hộp thư thông báo (GET/PATCH /notification-settings) — ttlHours = số giờ 1
/// thông báo được giữ trước khi bị sweep nền tự xoá (server/src/push.js sweepOldNotifications),
/// null = không tự xoá.
class NotificationSettings {
  final String? id;
  final int? ttlHours;

  NotificationSettings({this.id, this.ttlHours});

  factory NotificationSettings.fromJson(Map<String, dynamic>? json) => NotificationSettings(
        id: json?['id'] as String?,
        ttlHours: (json?['ttl_hours'] as num?)?.toInt(),
      );
}
