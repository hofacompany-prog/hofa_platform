class Address {
  final String id;
  final String? label;
  final String recipientName;
  final String recipientPhone;
  final String line1;
  final String? ward;
  final String? district;
  final String province;
  final bool isDefault;
  final double? latitude;
  final double? longitude;

  Address({
    required this.id,
    this.label,
    required this.recipientName,
    required this.recipientPhone,
    required this.line1,
    this.ward,
    this.district,
    required this.province,
    required this.isDefault,
    this.latitude,
    this.longitude,
  });

  factory Address.fromJson(Map<String, dynamic> json) => Address(
    id: json['id'] as String,
    label: json['label'] as String?,
    recipientName: json['recipient_name'] as String? ?? '',
    recipientPhone: json['recipient_phone'] as String? ?? '',
    line1: json['line1'] as String? ?? '',
    ward: json['ward'] as String?,
    district: json['district'] as String?,
    province: json['province'] as String? ?? '',
    isDefault: json['is_default'] as bool? ?? false,
    latitude: double.tryParse('${json['latitude']}'),
    longitude: double.tryParse('${json['longitude']}'),
  );

  String get fullLine => [
    line1,
    ward,
    district,
    province,
  ].where((e) => e != null && e.isNotEmpty).join(', ');
}
