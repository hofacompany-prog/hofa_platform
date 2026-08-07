/// 1 thiết bị đã từng đăng nhập tài khoản này (bảng user_devices) — dùng để hiện màn
/// "Thiết bị đã đăng nhập" trong Cài đặt. [deviceId] là mã máy app tự sinh (khác [id], khoá
/// chính của dòng), dùng để so với DeviceRepository.currentDeviceId() và đánh dấu thiết bị
/// đang dùng để xem màn này.
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
