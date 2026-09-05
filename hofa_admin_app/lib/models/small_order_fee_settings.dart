/// Phí cộng thêm cho đơn giá trị nhỏ — áp dụng MỌI cửa hàng (không riêng mua hộ). Đơn có
/// subtotal (đã gồm % phí mua hộ nếu có) dưới [thresholdAmount] thì total_amount cộng thêm
/// [feeAmount]. Xem hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql.
class SmallOrderFeeSettings {
  final String? id;
  final bool isActive;
  final int thresholdAmount;
  final int feeAmount;

  SmallOrderFeeSettings({
    this.id,
    this.isActive = true,
    required this.thresholdAmount,
    required this.feeAmount,
  });

  factory SmallOrderFeeSettings.fromJson(Map<String, dynamic> json) =>
      SmallOrderFeeSettings(
        id: json['id'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        thresholdAmount: (json['threshold_amount'] as num?)?.toInt() ?? 30000,
        feeAmount: (json['fee_amount'] as num?)?.toInt() ?? 5000,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory SmallOrderFeeSettings.fallback() =>
      SmallOrderFeeSettings(thresholdAmount: 30000, feeAmount: 5000);

  Map<String, dynamic> toJson() => {
    'is_active': isActive,
    'threshold_amount': thresholdAmount,
    'fee_amount': feeAmount,
  };
}
