class Merchant {
  final String id;
  final String ownerId;
  final String name;
  final String slug;
  final String? description;
  final String merchantType;
  final String status;
  final String? phone;
  final num commissionRate;
  final int minOrderAmount;
  final num ratingAvg;
  final int ratingCount;

  Merchant({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.slug,
    this.description,
    required this.merchantType,
    required this.status,
    this.phone,
    required this.commissionRate,
    required this.minOrderAmount,
    required this.ratingAvg,
    required this.ratingCount,
  });

  factory Merchant.fromJson(Map<String, dynamic> json) => Merchant(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        description: json['description'] as String?,
        merchantType: json['merchant_type'] as String? ?? 'regular',
        status: json['status'] as String? ?? 'draft',
        phone: json['phone'] as String?,
        commissionRate: num.tryParse('${json['commission_rate']}') ?? 0,
        minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
        ratingAvg: num.tryParse('${json['rating_avg']}') ?? 0,
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      );
}
