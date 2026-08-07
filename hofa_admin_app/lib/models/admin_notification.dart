/// 1 lượt thông báo đẩy admin đã gửi — xem lịch sử ở màn Thông báo. audienceType = nhóm
/// (customer/merchant/driver), target = all (cả nhóm) hoặc specific (tự chọn).
class AdminNotification {
  final String id;
  final String title;
  final String body;
  final String audienceType;
  final String target;
  final int sentCount;
  final int totalCount;
  final bool showBadge;
  final String? targetScreen;
  final String category;
  final DateTime createdAt;
  final String? createdByName;
  final List<String> recipientNames;
  final List<String> targetMerchantNames;

  AdminNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.audienceType,
    required this.target,
    required this.sentCount,
    required this.totalCount,
    required this.createdAt,
    this.showBadge = false,
    this.targetScreen,
    this.category = 'system',
    this.createdByName,
    this.recipientNames = const [],
    this.targetMerchantNames = const [],
  });

  factory AdminNotification.fromJson(Map<String, dynamic> json) =>
      AdminNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        audienceType: json['audience_type'] as String? ?? 'customer',
        target: json['target'] as String? ?? 'all',
        sentCount: (json['sent_count'] as num?)?.toInt() ?? 0,
        totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
        showBadge: json['show_badge'] as bool? ?? false,
        targetScreen: json['target_screen'] as String?,
        category: json['category'] as String? ?? 'system',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        createdByName: json['created_by_name'] as String?,
        recipientNames:
            (json['recipient_names'] as List?)?.cast<String>() ?? const [],
        targetMerchantNames:
            (json['target_merchant_names'] as List?)?.cast<String>() ??
            const [],
      );
}

const audienceTypeLabels = {
  'customer': 'Khách hàng',
  'merchant': 'Cửa hàng',
  'driver': 'Tài xế',
};

/// Danh mục hiển thị theo tab trong hộp thư của app nhận (Tất cả/Đơn hàng/Khuyến mãi/Quảng
/// cáo...) — 'order' do hệ thống tự gắn cho thông báo đơn hàng/chuyến giao, không chọn được
/// ở đây (chỉ liệt kê để hiện nhãn đúng trong lịch sử nếu có), 3 cái còn lại admin tự chọn.
const notificationCategoryLabels = {
  'order': 'Đơn hàng',
  'promotion': 'Khuyến mãi',
  'ad': 'Quảng cáo',
  'system': 'Khác',
};

/// Màn app sẽ mở khi người dùng bấm vào thông báo — khác nhau theo audienceType vì mỗi
/// app (customer/store/driver) có route riêng. Giá trị (key) là route thật của app đó, xem
/// core/push_service.dart của từng app để biết nó xử lý route này thế nào.
const Map<String, Map<String, String>> notificationTargetScreensByAudience = {
  'customer': {
    '/': 'Trang chủ',
    '/orders': 'Đơn hàng của tôi',
    '/cart': 'Giỏ hàng',
    '/profile': 'Hồ sơ',
  },
  'merchant': {
    '/products': 'Sản phẩm (trang chủ)',
    '/orders': 'Đơn hàng',
    '/inventory': 'Kho hàng',
    '/settings': 'Cài đặt',
  },
  'driver': {
    '/': 'Trang chủ',
    '/earnings': 'Thu nhập',
    '/profile': 'Hồ sơ',
  },
};
