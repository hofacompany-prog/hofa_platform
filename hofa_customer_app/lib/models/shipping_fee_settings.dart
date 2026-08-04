/// Cấu hình phí ship toàn sàn (chỉnh ở app admin). Công thức: phí ship = baseFee (cho
/// baseDistanceKm đầu) + perKmFee × (số km vượt baseDistanceKm, nếu > 0), làm tròn theo
/// roundTo, không vượt quá maxFee (nếu có), và bằng 0 nếu tổng đơn hàng ≥ freeShipThreshold
/// (nếu có). App khách chỉ đọc để ước tính, không tự tính vào đơn hàng thật.
class ShippingFeeSettings {
  final bool isActive;
  final int baseFee;
  final double baseDistanceKm;
  final int perKmFee;
  final int? freeShipThreshold;
  final int? maxFee;
  final int roundTo;

  ShippingFeeSettings({
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
        isActive: json['is_active'] as bool? ?? true,
        baseFee: (json['base_fee'] as num?)?.toInt() ?? 0,
        // NUMERIC ở Postgres về qua node-postgres là String, không phải num.
        baseDistanceKm: double.tryParse('${json['base_distance_km']}') ?? 0,
        perKmFee: (json['per_km_fee'] as num?)?.toInt() ?? 0,
        freeShipThreshold: (json['free_ship_threshold'] as num?)?.toInt(),
        maxFee: (json['max_fee'] as num?)?.toInt(),
        roundTo: (json['round_to'] as num?)?.toInt() ?? 500,
      );

  /// Ước tính phí ship cho [distanceKm]/[orderAmount] — đúng công thức backend sẽ áp
  /// dụng thật khi tính năng được nối vào lúc tạo đơn.
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
}
