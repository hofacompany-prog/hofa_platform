/// 1 bậc giảm giá theo giá trị đơn của 1 voucher — voucher không có bậc nào thì dùng nguyên
/// discount_value/max_discount của chính voucher như trước (tương thích ngược).
class VoucherAmountTier {
  final String id;
  final String voucherId;
  final int minOrderAmount;
  final int discountValue;
  final int? maxDiscount;

  VoucherAmountTier({
    required this.id,
    required this.voucherId,
    required this.minOrderAmount,
    required this.discountValue,
    this.maxDiscount,
  });

  factory VoucherAmountTier.fromJson(Map<String, dynamic> json) => VoucherAmountTier(
        id: json['id'] as String,
        voucherId: json['voucher_id'] as String,
        minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
        discountValue: (json['discount_value'] as num?)?.toInt() ?? 0,
        maxDiscount: (json['max_discount'] as num?)?.toInt(),
      );
}
