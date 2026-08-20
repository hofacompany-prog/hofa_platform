/// Bán kính tối đa (mét) giữa tài xế và chi nhánh lúc xác nhận "Đã lấy hàng" cho đơn mua hộ —
/// xem server/src/routes/deliveries.js (PATCH /deliveries/:id/status), hofa-db/
/// 91_buy_on_behalf_pickup_proximity.sql.
class PickupProximitySettings {
  final String? id;
  final int maxDistanceMeters;

  PickupProximitySettings({this.id, required this.maxDistanceMeters});

  factory PickupProximitySettings.fromJson(Map<String, dynamic> json) =>
      PickupProximitySettings(
        id: json['id'] as String?,
        maxDistanceMeters: (json['max_distance_meters'] as num?)?.toInt() ?? 100,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory PickupProximitySettings.fallback() =>
      PickupProximitySettings(maxDistanceMeters: 100);

  Map<String, dynamic> toJson() => {'max_distance_meters': maxDistanceMeters};
}
