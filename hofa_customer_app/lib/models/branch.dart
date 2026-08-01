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
