class MerchantOwner {
  final String id;
  final String fullName;
  final String phone;
  final String? email;

  MerchantOwner({required this.id, required this.fullName, required this.phone, this.email});

  factory MerchantOwner.fromJson(Map<String, dynamic> json) => MerchantOwner(
        id: json['id'] as String,
        fullName: json['full_name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String?,
      );
}

class Branch {
  final String id;
  final String merchantId;
  final String name;
  final String? phone;
  final String line1;
  final String? ward;
  final String? district;
  final String province;
  final bool isMain;
  final bool isOpen;

  Branch({
    required this.id,
    required this.merchantId,
    required this.name,
    this.phone,
    required this.line1,
    this.ward,
    this.district,
    required this.province,
    required this.isMain,
    required this.isOpen,
  });

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        line1: json['line1'] as String? ?? '',
        ward: json['ward'] as String?,
        district: json['district'] as String?,
        province: json['province'] as String? ?? '',
        isMain: json['is_main'] as bool? ?? false,
        isOpen: json['is_open'] as bool? ?? true,
      );

  String get fullLine => [line1, ward, district, province].where((e) => e != null && e.isNotEmpty).join(', ');
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
  final String? bankName;
  final String? bankAccountNo;
  final String? bankAccountName;
  final num commissionRate;
  final int minOrderAmount;
  final int avgPrepMinutes;
  final num ratingAvg;
  final int ratingCount;
  final DateTime? standardCertifiedAt;
  final DateTime? createdAt;
  // Chỉ có khi gọi GET /merchants/:id với quyền admin/chủ (server nhúng sẵn).
  final MerchantOwner? owner;
  final List<Branch>? branches;

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
    this.bankName,
    this.bankAccountNo,
    this.bankAccountName,
    required this.commissionRate,
    required this.minOrderAmount,
    required this.avgPrepMinutes,
    required this.ratingAvg,
    required this.ratingCount,
    this.standardCertifiedAt,
    this.createdAt,
    this.owner,
    this.branches,
  });

  bool get isStandard => standardCertifiedAt != null;

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
        bankName: json['bank_name'] as String?,
        bankAccountNo: json['bank_account_no'] as String?,
        bankAccountName: json['bank_account_name'] as String?,
        commissionRate: num.tryParse('${json['commission_rate']}') ?? 0,
        minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
        avgPrepMinutes: (json['avg_prep_minutes'] as num?)?.toInt() ?? 15,
        ratingAvg: num.tryParse('${json['rating_avg']}') ?? 0,
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
        standardCertifiedAt:
            json['standard_certified_at'] != null ? DateTime.tryParse(json['standard_certified_at'] as String) : null,
        createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
        owner: json['owner'] != null ? MerchantOwner.fromJson(json['owner'] as Map<String, dynamic>) : null,
        branches: json['branches'] != null
            ? (json['branches'] as List).map((e) => Branch.fromJson(e as Map<String, dynamic>)).toList()
            : null,
      );
}
