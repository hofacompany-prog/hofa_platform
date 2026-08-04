/// Voucher công khai (isPublic ở phía admin) — hiện thành danh sách cho khách chọn ngay ở
/// màn thanh toán, không cần gõ mã (xem voucher_picker_dialog.dart).
class Voucher {
  final String id;
  final String code;
  final String? description;
  final String discountType; // 'percent' | 'fixed' | 'free_shipping'
  final int discountValue;
  final int? maxDiscount;
  final int minOrderAmount;
  final DateTime? endsAt;

  Voucher({
    required this.id,
    required this.code,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.maxDiscount,
    required this.minOrderAmount,
    this.endsAt,
  });

  factory Voucher.fromJson(Map<String, dynamic> json) => Voucher(
    id: json['id'] as String,
    code: json['code'] as String? ?? '',
    description: json['description'] as String?,
    discountType: json['discount_type'] as String? ?? 'fixed',
    discountValue: (json['discount_value'] as num?)?.toInt() ?? 0,
    maxDiscount: (json['max_discount'] as num?)?.toInt(),
    minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
    endsAt: json['ends_at'] != null
        ? DateTime.tryParse(json['ends_at'] as String)
        : null,
  );

  bool get isExpired => endsAt != null && endsAt!.isBefore(DateTime.now());

  /// Mô tả ngắn số tiền/tỉ lệ giảm, dùng hiển thị trong danh sách chọn voucher.
  String discountLabel(String Function(num) formatVnd) {
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

class VoucherValidation {
  final bool valid;
  final String? reason;
  final String? discountType;
  final int estimatedDiscount;

  VoucherValidation({
    required this.valid,
    this.reason,
    this.discountType,
    required this.estimatedDiscount,
  });

  factory VoucherValidation.fromJson(Map<String, dynamic> json) =>
      VoucherValidation(
        valid: json['valid'] as bool? ?? false,
        reason: json['reason'] as String?,
        discountType: json['discount_type'] as String?,
        estimatedDiscount: (json['estimated_discount'] as num?)?.toInt() ?? 0,
      );
}
