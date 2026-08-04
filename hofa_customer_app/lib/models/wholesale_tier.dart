/// Bậc giá theo số lượng của 1 biến thể. minDaysPerWeek == 0 nghĩa là bậc "Giá sỉ" (chỉ
/// 1 điều kiện số lượng, dùng đúng 1 giá unitPrice). minDaysPerWeek > 0 nghĩa là bậc
/// "Đặt trước" — có 2 điều kiện độc lập: số lượng (tổng phần cùng 1 lần giao) và số
/// ngày/tuần khách đặt RIÊNG sản phẩm này — 3 giá tương ứng: chỉ đạt số lượng (unitPrice),
/// chỉ đạt số ngày (unitPriceDays), đạt cả 2 (unitPriceBoth).
class WholesaleTier {
  final String id;
  final String variantId;
  final int minQuantity;
  final int? maxQuantity;
  final int unitPrice;
  final int minDaysPerWeek;
  final int? unitPriceDays;
  final int? unitPriceBoth;
  final bool requiresDeposit;
  final double depositPercent;

  WholesaleTier({
    required this.id,
    required this.variantId,
    required this.minQuantity,
    this.maxQuantity,
    required this.unitPrice,
    required this.minDaysPerWeek,
    this.unitPriceDays,
    this.unitPriceBoth,
    required this.requiresDeposit,
    required this.depositPercent,
  });

  factory WholesaleTier.fromJson(Map<String, dynamic> json) => WholesaleTier(
    id: json['id'] as String,
    variantId: json['variant_id'] as String,
    minQuantity: (json['min_quantity'] as num?)?.toInt() ?? 0,
    maxQuantity: (json['max_quantity'] as num?)?.toInt(),
    unitPrice: (json['unit_price'] as num?)?.toInt() ?? 0,
    minDaysPerWeek: (json['min_days_per_week'] as num?)?.toInt() ?? 0,
    unitPriceDays: (json['unit_price_days'] as num?)?.toInt(),
    unitPriceBoth: (json['unit_price_both'] as num?)?.toInt(),
    requiresDeposit: json['requires_deposit'] as bool? ?? false,
    // NUMERIC ở Postgres về qua node-postgres là String, không phải num.
    depositPercent: (num.tryParse('${json['deposit_percent']}') ?? 0)
        .toDouble(),
  );

  String get rangeLabel => maxQuantity != null
      ? '$minQuantity - $maxQuantity'
      : 'Từ $minQuantity trở lên';
}
