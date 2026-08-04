/// Cấu hình phí ship toàn sàn. Công thức: phí ship = baseFee (cho baseDistanceKm đầu) +
/// perKmFee × (số km vượt baseDistanceKm, nếu > 0), làm tròn theo roundTo, không vượt quá
/// maxFee (nếu có), và bằng 0 nếu tổng đơn hàng ≥ freeShipThreshold (nếu có).
class ShippingFeeSettings {
  final String? id;
  final bool isActive;
  final int baseFee;
  final double baseDistanceKm;
  final int perKmFee;
  final int? freeShipThreshold;
  final int? maxFee;
  final int roundTo;

  ShippingFeeSettings({
    this.id,
    required this.isActive,
    required this.baseFee,
    required this.baseDistanceKm,
    required this.perKmFee,
    this.freeShipThreshold,
    this.maxFee,
    required this.roundTo,
  });

  factory ShippingFeeSettings.fromJson(Map<String, dynamic> json) =>
      ShippingFeeSettings(
        id: json['id'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        baseFee: (json['base_fee'] as num?)?.toInt() ?? 0,
        // NUMERIC ở Postgres về qua node-postgres là String, không phải num.
        baseDistanceKm: double.tryParse('${json['base_distance_km']}') ?? 0,
        perKmFee: (json['per_km_fee'] as num?)?.toInt() ?? 0,
        freeShipThreshold: (json['free_ship_threshold'] as num?)?.toInt(),
        maxFee: (json['max_fee'] as num?)?.toInt(),
        roundTo: (json['round_to'] as num?)?.toInt() ?? 500,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory ShippingFeeSettings.fallback() => ShippingFeeSettings(
    isActive: true,
    baseFee: 15000,
    baseDistanceKm: 2,
    perKmFee: 4000,
    roundTo: 500,
  );

  /// Ước tính phí ship cho [distanceKm]/[orderAmount] — dùng để xem trước ngay trên màn
  /// cài đặt, đúng công thức backend sẽ áp dụng thật.
  int estimate(double distanceKm, {int orderAmount = 0}) {
    if (!isActive) return 0;
    if (freeShipThreshold != null && orderAmount >= freeShipThreshold!) {
      return 0;
    }
    final extraKm = distanceKm - baseDistanceKm;
    var fee = baseFee + (extraKm > 0 ? extraKm * perKmFee : 0);
    fee = (fee / roundTo).round() * roundTo;
    if (maxFee != null && fee > maxFee!) fee = maxFee!.toDouble();
    return fee.round();
  }

  Map<String, dynamic> toJson() => {
    'is_active': isActive,
    'base_fee': baseFee,
    'base_distance_km': baseDistanceKm,
    'per_km_fee': perKmFee,
    'free_ship_threshold': freeShipThreshold,
    'max_fee': maxFee,
    'round_to': roundTo,
  };
}
