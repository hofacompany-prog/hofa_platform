import 'merchant_classification.dart';

class MerchantOwner {
  final String id;
  final String fullName;
  final String phone;
  final String? email;

  MerchantOwner({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
  });

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
  final double latitude;
  final double longitude;
  final bool isMain;
  final bool isOpen;
  final num deliveryRadiusKm;

  Branch({
    required this.id,
    required this.merchantId,
    required this.name,
    this.phone,
    required this.line1,
    this.ward,
    this.district,
    required this.province,
    required this.latitude,
    required this.longitude,
    required this.isMain,
    required this.isOpen,
    required this.deliveryRadiusKm,
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
    latitude: double.tryParse('${json['latitude']}') ?? 0,
    longitude: double.tryParse('${json['longitude']}') ?? 0,
    isMain: json['is_main'] as bool? ?? false,
    isOpen: json['is_open'] as bool? ?? true,
    deliveryRadiusKm: num.tryParse('${json['delivery_radius_km']}') ?? 5,
  );

  String get fullLine => [
    line1,
    ward,
    district,
    province,
  ].where((e) => e != null && e.isNotEmpty).join(', ');
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
  final int maxDevices;
  final num vatRate;
  final num pitRate;
  final num ratingAvg;
  final int ratingCount;
  final DateTime? standardCertifiedAt;
  // Chỉ có ý nghĩa khi merchantType == 'buy_on_behalf' — 'quantity' hoặc 'value', xem
  // merchant_fee_tiers (bậc phí mua hộ, admin cấu hình riêng ở màn chi tiết cửa hàng).
  final String? buyOnBehalfFeeBasis;
  final DateTime? createdAt;
  // Chỉ có khi gọi GET /merchants/:id với quyền admin/chủ (server nhúng sẵn).
  final MerchantOwner? owner;
  final List<Branch>? branches;
  final List<MerchantClassification> classifications;

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
    this.maxDevices = 1,
    this.vatRate = 3.0,
    this.pitRate = 1.5,
    required this.ratingAvg,
    required this.ratingCount,
    this.standardCertifiedAt,
    this.buyOnBehalfFeeBasis,
    this.createdAt,
    this.owner,
    this.branches,
    this.classifications = const [],
  });

  bool get isStandard => standardCertifiedAt != null;
  bool get isBuyOnBehalf => merchantType == 'buy_on_behalf';

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
    legalDocUrls: json['legal_doc_urls'] is List
        ? (json['legal_doc_urls'] as List).map((e) => e.toString()).toList()
        : const [],
    photoUrls: json['photo_urls'] is List
        ? (json['photo_urls'] as List).map((e) => e.toString()).toList()
        : const [],
    bankName: json['bank_name'] as String?,
    bankAccountNo: json['bank_account_no'] as String?,
    bankAccountName: json['bank_account_name'] as String?,
    commissionRate: num.tryParse('${json['commission_rate']}') ?? 0,
    minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
    avgPrepMinutes: (json['avg_prep_minutes'] as num?)?.toInt() ?? 15,
    maxDevices: (json['max_devices'] as num?)?.toInt() ?? 1,
    vatRate: num.tryParse('${json['vat_rate']}') ?? 3.0,
    pitRate: num.tryParse('${json['pit_rate']}') ?? 1.5,
    ratingAvg: num.tryParse('${json['rating_avg']}') ?? 0,
    ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
    standardCertifiedAt: json['standard_certified_at'] != null
        ? DateTime.tryParse(json['standard_certified_at'] as String)
        : null,
    buyOnBehalfFeeBasis: json['buy_on_behalf_fee_basis'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
    owner: json['owner'] != null
        ? MerchantOwner.fromJson(json['owner'] as Map<String, dynamic>)
        : null,
    branches: json['branches'] != null
        ? (json['branches'] as List)
              .map((e) => Branch.fromJson(e as Map<String, dynamic>))
              .toList()
        : null,
    classifications: json['classifications'] is List
        ? (json['classifications'] as List)
              .map(
                (e) =>
                    MerchantClassification.fromJson(e as Map<String, dynamic>),
              )
              .toList()
        : const [],
  );
}
