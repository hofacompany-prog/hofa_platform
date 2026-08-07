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
  // 'quantity' hoặc 'value' — chỉ có ý nghĩa khi merchantType == 'buy_on_behalf', quyết
  // định bảng phí mua hộ (merchant_fee_tiers) tính ngưỡng theo gì.
  final String? buyOnBehalfFeeBasis;
  // true nếu còn ít nhất 1 chi nhánh đang mở cửa (branches.is_open) — cửa hàng không còn chi
  // nhánh nào mở thì khách vẫn xem được sản phẩm nhưng không đặt hàng được (server chặn thật
  // ở POST /orders, đây chỉ để app tự xám giao diện/khoá nút trước khi khách bấm).
  final bool hasOpenBranch;

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
    this.buyOnBehalfFeeBasis,
    this.hasOpenBranch = true,
  });

  bool get isStandard => standardCertifiedAt != null;
  bool get isBuyOnBehalf => merchantType == 'buy_on_behalf';

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
        buyOnBehalfFeeBasis: json['buy_on_behalf_fee_basis'] as String?,
        hasOpenBranch: json['has_open_branch'] as bool? ?? true,
      );
}
