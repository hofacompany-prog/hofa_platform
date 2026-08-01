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
        name: json['name'] as String,
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

  String get fullLine => [line1, ward, district, province].where((e) => e != null && e.isNotEmpty).join(', ');
}
