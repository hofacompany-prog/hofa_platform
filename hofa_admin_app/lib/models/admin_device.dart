/// 1 thiết bị đã đăng nhập của MỘT TRONG CÁC tài khoản admin (GET /admin/admin-devices) —
/// dùng ở tab "Thiết bị admin" (notifications_screen.dart) để tự soát máy lạ, tắt/xoá.
class AdminDevice {
  final String id;
  final String userId;
  final String userFullName;
  final String deviceId;
  final String? deviceName;
  final String? platform;
  final bool hasPushToken;
  final DateTime? lastActiveAt;
  final DateTime createdAt;

  AdminDevice({
    required this.id,
    required this.userId,
    required this.userFullName,
    required this.deviceId,
    this.deviceName,
    this.platform,
    required this.hasPushToken,
    this.lastActiveAt,
    required this.createdAt,
  });

  factory AdminDevice.fromJson(Map<String, dynamic> json) => AdminDevice(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    userFullName: json['user_full_name'] as String? ?? '',
    deviceId: json['device_id'] as String? ?? '',
    deviceName: json['device_name'] as String?,
    platform: json['platform'] as String?,
    hasPushToken: json['push_token'] != null,
    lastActiveAt: json['last_active_at'] != null
        ? DateTime.tryParse(json['last_active_at'] as String)
        : null,
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );
}

const adminDevicePlatformLabels = {
  'ios': 'iPhone/iPad',
  'android': 'Android',
  'web': 'Trình duyệt',
};
