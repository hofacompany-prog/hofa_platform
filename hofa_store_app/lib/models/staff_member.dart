/// Nhân viên cửa hàng (merchant_staff) — tài khoản đăng nhập riêng (do chủ cửa hàng tạo bằng
/// SĐT + mật khẩu), chỉ làm được đúng phần việc trong [permissions].
class StaffMember {
  final String id;
  final String merchantId;
  final String? branchId;
  final String userId;
  final String fullName;
  final String phone;
  final String? position;
  final List<String> permissions;

  StaffMember({
    required this.id,
    required this.merchantId,
    this.branchId,
    required this.userId,
    required this.fullName,
    required this.phone,
    this.position,
    required this.permissions,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
    id: json['id'] as String,
    merchantId: json['merchant_id'] as String,
    branchId: json['branch_id'] as String?,
    userId: json['user_id'] as String,
    fullName: json['full_name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    position: json['position'] as String?,
    permissions:
        (json['permissions'] as List?)?.map((e) => e.toString()).toList() ??
        [],
  );
}

/// Danh sách quyền hợp lệ + nhãn tiếng Việt — dùng cho form thêm/sửa nhân viên VÀ để lọc điều
/// hướng theo quyền (xem myPermissionsProvider). Khớp đúng STAFF_PERMISSIONS ở
/// server/src/routes/merchants.js.
const kStaffPermissionLabels = {
  'products.view': 'Xem sản phẩm',
  'products.manage': 'Thêm/sửa/xoá sản phẩm',
  'orders.view': 'Xem đơn hàng',
  'orders.manage': 'Xác nhận/chuẩn bị/huỷ đơn',
  'inventory.manage': 'Điều chỉnh tồn kho',
  'finance.view': 'Xem tài chính',
};
