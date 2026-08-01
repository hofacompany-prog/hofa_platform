class WholesaleTier {
  final String id;
  final String variantId;
  final int minQuantity;
  final int? maxQuantity;
  final int unitPrice;
  final int leadTimeDays;
  final bool requiresDeposit;
  final double depositPercent;

  WholesaleTier({
    required this.id,
    required this.variantId,
    required this.minQuantity,
    this.maxQuantity,
    required this.unitPrice,
    required this.leadTimeDays,
    required this.requiresDeposit,
    required this.depositPercent,
  });

  factory WholesaleTier.fromJson(Map<String, dynamic> json) => WholesaleTier(
        id: json['id'] as String,
        variantId: json['variant_id'] as String,
        minQuantity: (json['min_quantity'] as num?)?.toInt() ?? 0,
        maxQuantity: (json['max_quantity'] as num?)?.toInt(),
        unitPrice: (json['unit_price'] as num?)?.toInt() ?? 0,
        leadTimeDays: (json['lead_time_days'] as num?)?.toInt() ?? 0,
        requiresDeposit: json['requires_deposit'] as bool? ?? false,
        depositPercent: (json['deposit_percent'] as num?)?.toDouble() ?? 0,
      );

  String get rangeLabel => maxQuantity != null ? '$minQuantity - $maxQuantity' : 'Từ $minQuantity trở lên';
}
