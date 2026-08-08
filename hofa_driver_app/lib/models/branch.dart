import '../core/format.dart';

class Branch {
  final String id;
  final String merchantId;
  final String name;
  final String? merchantName;
  final String? merchantType;
  final String? phone;
  final String line1;
  final String? ward;
  final String? district;
  final String province;
  final double latitude;
  final double longitude;

  Branch({
    required this.id,
    required this.merchantId,
    required this.name,
    this.merchantName,
    this.merchantType,
    this.phone,
    required this.line1,
    this.ward,
    this.district,
    required this.province,
    required this.latitude,
    required this.longitude,
  });

  String get fullLine => [line1, ward, district, province].where((e) => e != null && e.isNotEmpty).join(', ');

  /// Tên quán trước, tên chi nhánh sau — xem pickupTitle trong core/format.dart.
  String get displayName => pickupTitle(merchantName, name);

  /// Đơn mua hộ — tài xế tự đi mua, không có OTP/nhân viên xác nhận lấy hàng.
  bool get isBuyOnBehalf => merchantType == 'buy_on_behalf';

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        name: json['name'] as String? ?? '',
        merchantName: json['merchant_name'] as String?,
        merchantType: json['merchant_type'] as String?,
        phone: json['phone'] as String?,
        line1: json['line1'] as String? ?? '',
        ward: json['ward'] as String?,
        district: json['district'] as String?,
        province: json['province'] as String? ?? '',
        latitude: double.tryParse('${json['latitude']}') ?? 0,
        longitude: double.tryParse('${json['longitude']}') ?? 0,
      );
}
