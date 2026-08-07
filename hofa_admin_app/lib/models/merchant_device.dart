/// 1 thiết bị đã đăng nhập của chủ/nhân viên 1 cửa hàng (GET /merchants/:id/devices) —
/// dùng ở màn chi tiết cửa hàng trong web admin để admin xem/tắt/xoá.
class MerchantDevice {
  final String id;
  final String userId;
  final String userFullName;
  final String userRole;
  final String? deviceName;
  final String? platform;
  final bool hasPushToken;
  final DateTime? lastActiveAt;
  final DateTime createdAt;

  MerchantDevice({
    required this.id,
    required this.userId,
    required this.userFullName,
    required this.userRole,
    this.deviceName,
    this.platform,
    required this.hasPushToken,
    this.lastActiveAt,
    required this.createdAt,
  });

  factory MerchantDevice.fromJson(Map<String, dynamic> json) => MerchantDevice(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        userFullName: json['user_full_name'] as String? ?? '',
        userRole: json['user_role'] as String? ?? '',
        deviceName: json['device_name'] as String?,
        platform: json['platform'] as String?,
        hasPushToken: json['push_token'] != null,
        lastActiveAt: json['last_active_at'] != null
            ? DateTime.tryParse(json['last_active_at'] as String)
            : null,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

const merchantDevicePlatformLabels = {'ios': 'iPhone/iPad', 'android': 'Android', 'web': 'Trình duyệt'};
const merchantUserRoleLabels = {'merchant_owner': 'Chủ cửa hàng', 'merchant_staff': 'Nhân viên'};
