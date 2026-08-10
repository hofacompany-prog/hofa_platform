List<String> _parseUrlList(dynamic raw) {
  if (raw is! List) return [];
  return raw.map((e) => e.toString()).toList();
}

class Merchant {
  final String id;
  final String ownerId;
  final String name;
  final String slug;
  final String? description;
  final String merchantType;
  final String status;
  final String? logoUrl;
  final String? coverUrl;
  final String? phone;
  final String? email;
  final String? businessLicenseNo;
  final String? taxCode;
  final List<String> legalDocUrls;

  /// Ảnh cửa hàng (không phải logo/bìa/giấy tờ) — hiện cạnh logo ở màn chi tiết cửa hàng.
  final List<String> photoUrls;
  final String? bankName;
  final String? bankBin;
  final String? bankAccountNo;
  final String? bankAccountName;
  final num commissionRate;
  final int minOrderAmount;
  final int avgPrepMinutes;
  final num ratingAvg;
  final int ratingCount;

  /// null = chủ cửa hàng (full quyền); mảng (kể cả rỗng) = nhân viên, đúng danh sách quyền
  /// được cấp trong merchant_staff.permissions. Xem myPermissionsProvider.
  final List<String>? myPermissions;

  Merchant({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.slug,
    this.description,
    required this.merchantType,
    required this.status,
    this.logoUrl,
    this.coverUrl,
    this.phone,
    this.email,
    this.businessLicenseNo,
    this.taxCode,
    this.legalDocUrls = const [],
    this.photoUrls = const [],
    this.bankName,
    this.bankBin,
    this.bankAccountNo,
    this.bankAccountName,
    required this.commissionRate,
    required this.minOrderAmount,
    required this.avgPrepMinutes,
    required this.ratingAvg,
    required this.ratingCount,
    this.myPermissions,
  });

  factory Merchant.fromJson(Map<String, dynamic> json) => Merchant(
    id: json['id'] as String,
    ownerId: json['owner_id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    description: json['description'] as String?,
    merchantType: json['merchant_type'] as String? ?? 'regular',
    status: json['status'] as String? ?? 'draft',
    logoUrl: json['logo_url'] as String?,
    coverUrl: json['cover_url'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    businessLicenseNo: json['business_license_no'] as String?,
    taxCode: json['tax_code'] as String?,
    legalDocUrls: _parseUrlList(json['legal_doc_urls']),
    photoUrls: _parseUrlList(json['photo_urls']),
    bankName: json['bank_name'] as String?,
    bankBin: json['bank_bin'] as String?,
    bankAccountNo: json['bank_account_no'] as String?,
    bankAccountName: json['bank_account_name'] as String?,
    commissionRate: num.tryParse('${json['commission_rate']}') ?? 0,
    minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
    avgPrepMinutes: (json['avg_prep_minutes'] as num?)?.toInt() ?? 15,
    ratingAvg: num.tryParse('${json['rating_avg']}') ?? 0,
    ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
    myPermissions: (json['my_permissions'] as List?)
        ?.map((e) => e.toString())
        .toList(),
  );
}
