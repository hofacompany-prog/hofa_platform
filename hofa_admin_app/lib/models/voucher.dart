/// Mã giảm giá. merchant_id null nghĩa là mã dùng cho toàn sàn HOFA. isPublic quyết định
/// mã này hiện thành danh sách cho khách chọn (kiểu Shopee) hay chỉ dùng được khi khách tự
/// gõ đúng mã.
class Voucher {
  final String id;
  final String code;
  final String? merchantId;
  final String? description;
  final String discountType; // 'percent' | 'fixed' | 'free_shipping'
  final int discountValue;
  final int? maxDiscount;
  final int minOrderAmount;
  final int? usageLimit;
  final int usageLimitPerUser;
  final int usedCount;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final bool isPublic;
  final DateTime? createdAt;

  Voucher({
    required this.id,
    required this.code,
    this.merchantId,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.maxDiscount,
    required this.minOrderAmount,
    this.usageLimit,
    required this.usageLimitPerUser,
    required this.usedCount,
    required this.startsAt,
    this.endsAt,
    required this.isActive,
    required this.isPublic,
    this.createdAt,
  });

  factory Voucher.fromJson(Map<String, dynamic> json) => Voucher(
    id: json['id'] as String,
    code: json['code'] as String? ?? '',
    merchantId: json['merchant_id'] as String?,
    description: json['description'] as String?,
    discountType: json['discount_type'] as String? ?? 'fixed',
    discountValue: (json['discount_value'] as num?)?.toInt() ?? 0,
    maxDiscount: (json['max_discount'] as num?)?.toInt(),
    minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
    usageLimit: (json['usage_limit'] as num?)?.toInt(),
    usageLimitPerUser: (json['usage_limit_per_user'] as num?)?.toInt() ?? 1,
    usedCount: (json['used_count'] as num?)?.toInt() ?? 0,
    startsAt:
        DateTime.tryParse(json['starts_at'] as String? ?? '') ?? DateTime.now(),
    endsAt: json['ends_at'] != null
        ? DateTime.tryParse(json['ends_at'] as String)
        : null,
    isActive: json['is_active'] as bool? ?? true,
    isPublic: json['is_public'] as bool? ?? false,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
  );

  bool get isExpired => endsAt != null && endsAt!.isBefore(DateTime.now());
  bool get isNotStartedYet => startsAt.isAfter(DateTime.now());
  bool get isUsedUp => usageLimit != null && usedCount >= usageLimit!;

  String get statusLabel {
    if (!isActive) return 'Đã tắt';
    if (isExpired) return 'Hết hạn';
    if (isNotStartedYet) return 'Chưa bắt đầu';
    if (isUsedUp) return 'Hết lượt';
    return 'Đang chạy';
  }

  /// Mô tả ngắn số tiền/tỉ lệ giảm, dùng hiển thị trên thẻ voucher.
  String discountLabel({required String Function(num) formatVnd}) {
    switch (discountType) {
      case 'percent':
        return maxDiscount != null
            ? 'Giảm $discountValue% (tối đa ${formatVnd(maxDiscount!)})'
            : 'Giảm $discountValue%';
      case 'free_shipping':
        return 'Miễn phí vận chuyển';
      default:
        return 'Giảm ${formatVnd(discountValue)}';
    }
  }
}
