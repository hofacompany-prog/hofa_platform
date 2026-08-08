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
        ratingAvg: (json['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
        distanceKm: json['distance_km'] != null ? (json['distance_km'] as num).toDouble() : null,
      );
}
