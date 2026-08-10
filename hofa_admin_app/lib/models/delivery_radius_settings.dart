/// Bán kính giao hàng mặc định toàn sàn — trần nới rộng thêm cho chi nhánh có bán kính riêng
/// (branches.delivery_radius_km) nhỏ hơn mức này, xem hofa-db/61_delivery_radius_settings.sql.
class DeliveryRadiusSettings {
  final String? id;
  final double defaultRadiusKm;

  DeliveryRadiusSettings({this.id, required this.defaultRadiusKm});

  factory DeliveryRadiusSettings.fromJson(Map<String, dynamic> json) =>
      DeliveryRadiusSettings(
        id: json['id'] as String?,
        // NUMERIC ở Postgres về qua node-postgres là String, không phải num.
        defaultRadiusKm: double.tryParse('${json['default_radius_km']}') ?? 5,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory DeliveryRadiusSettings.fallback() =>
      DeliveryRadiusSettings(defaultRadiusKm: 5);

  Map<String, dynamic> toJson() => {'default_radius_km': defaultRadiusKm};
}
