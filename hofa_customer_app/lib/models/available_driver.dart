/// Tài xế đang online, hiện ra để khách tự chọn cho đơn mua hộ — xem GET /drivers/available.
/// Chỉ chứa các trường công khai (server đã lọc sẵn, không có SĐT/giấy tờ/ví).
class AvailableDriver {
  final String id;
  final String fullName;
  final String? avatarUrl;
  final String? vehicleType;
  final String? vehiclePlate;
  final double ratingAvg;
  final int ratingCount;
  final double? distanceKm;

  AvailableDriver({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    this.vehicleType,
    this.vehiclePlate,
    required this.ratingAvg,
    required this.ratingCount,
    this.distanceKm,
  });

  factory AvailableDriver.fromJson(Map<String, dynamic> json) => AvailableDriver(
        id: json['id'] as String,
        fullName: json['full_name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        vehicleType: json['vehicle_type'] as String?,
        vehiclePlate: json['vehicle_plate'] as String?,
        // rating_avg là cột NUMERIC ở Postgres — node-postgres trả về dạng chuỗi (vd "0.00")
        // để tránh mất độ chính xác, không phải số JSON — ép thẳng "as num" sẽ ném lỗi
        // TypeError. Parse qua chuỗi giống hệt models/merchant.dart, models/product.dart.
        ratingAvg: (num.tryParse('${json['rating_avg']}') ?? 0).toDouble(),
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
        distanceKm: json['distance_km'] != null ? num.tryParse('${json['distance_km']}')?.toDouble() : null,
      );
}
