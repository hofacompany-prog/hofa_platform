class Merchant {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String merchantType;
  final String status;
  final String? logoUrl;
  final String? coverUrl;
  final String? phone;
  final int minOrderAmount;
  final int avgPrepMinutes;
  final double ratingAvg;
  final int ratingCount;
  final DateTime? standardCertifiedAt;

  Merchant({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.merchantType,
    required this.status,
    this.logoUrl,
    this.coverUrl,
    this.phone,
    required this.minOrderAmount,
    required this.avgPrepMinutes,
    required this.ratingAvg,
    required this.ratingCount,
    this.standardCertifiedAt,
  });

  bool get isStandard => standardCertifiedAt != null;

  factory Merchant.fromJson(Map<String, dynamic> json) => Merchant(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        description: json['description'] as String?,
        merchantType: json['merchant_type'] as String? ?? 'regular',
        status: json['status'] as String? ?? 'active',
        logoUrl: json['logo_url'] as String?,
        coverUrl: json['cover_url'] as String?,
        phone: json['phone'] as String?,
        minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
        avgPrepMinutes: (json['avg_prep_minutes'] as num?)?.toInt() ?? 15,
        // NUMERIC ở Postgres về qua node-postgres là String, không phải num.
        ratingAvg: (num.tryParse('${json['rating_avg']}') ?? 0).toDouble(),
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
        standardCertifiedAt:
            json['standard_certified_at'] != null ? DateTime.tryParse(json['standard_certified_at'] as String) : null,
      );
}
