class Address {
  final String id;
  final String? label;
  final String recipientName;
  final String recipientPhone;
  final String line1;
  final String? ward;
  final String? district;
  final String province;
  final double? latitude;
  final double? longitude;
  final String? note;
  final bool isDefault;

  Address({
    required this.id,
    this.label,
    required this.recipientName,
    required this.recipientPhone,
    required this.line1,
    this.ward,
    this.district,
    required this.province,
    this.latitude,
    this.longitude,
    this.note,
    required this.isDefault,
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
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        note: json['note'] as String?,
        isDefault: json['is_default'] as bool? ?? false,
      );

  String get fullLine => [line1, ward, district, province].where((e) => e != null && e.isNotEmpty).join(', ');
}
