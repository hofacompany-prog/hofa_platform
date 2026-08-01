class VoucherValidation {
  final bool valid;
  final String? reason;
  final String? discountType;
  final int estimatedDiscount;

  VoucherValidation({required this.valid, this.reason, this.discountType, required this.estimatedDiscount});

  factory VoucherValidation.fromJson(Map<String, dynamic> json) => VoucherValidation(
        valid: json['valid'] as bool? ?? false,
        reason: json['reason'] as String?,
        discountType: json['discount_type'] as String?,
        estimatedDiscount: (json['estimated_discount'] as num?)?.toInt() ?? 0,
      );
}
