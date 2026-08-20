/// 1 thiết bị đã từng đăng nhập tài khoản của người dùng (bảng user_devices) — admin xem/gỡ
/// thay người dùng, xem user_detail_screen.dart. Gỡ chỉ chặn được request KẾ TIẾP của máy đó
/// (DEVICE_REVOKED, xem server/src/middleware/auth.js), không thu hồi access_token hiện có
/// ngay lập tức.
class UserDevice {
  final String id;
  final String deviceId;
  final String? deviceName;
  final String? platform;
  final bool hasPushToken;
  final DateTime lastActiveAt;
  final DateTime createdAt;

  UserDevice({
    required this.id,
    required this.deviceId,
    this.deviceName,
    this.platform,
    required this.hasPushToken,
    required this.lastActiveAt,
    required this.createdAt,
  });

  factory UserDevice.fromJson(Map<String, dynamic> json) => UserDevice(
    id: json['id'] as String,
    deviceId: json['device_id'] as String? ?? '',
    deviceName: json['device_name'] as String?,
    platform: json['platform'] as String?,
    hasPushToken: json['push_token'] != null,
    lastActiveAt:
        DateTime.tryParse(json['last_active_at']?.toString() ?? '') ??
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );
}

const devicePlatformLabels = {'ios': 'iPhone/iPad', 'android': 'Android', 'web': 'Trình duyệt'};
