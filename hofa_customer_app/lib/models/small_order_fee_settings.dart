/// Phí cộng thêm cho đơn giá trị nhỏ — áp dụng TOÀN SÀN (mọi cửa hàng, kể cả mua hộ), tính
/// trên giá trị GIỎ HÀNG (subtotal — đã gồm % phí mua hộ nếu có), KHÔNG tính trên tổng thanh
/// toán cuối cùng (không gồm phí ship). Xem
/// hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql.
class SmallOrderFeeSettings {
  final bool isActive;
  final int thresholdAmount;
  final int feeAmount;

  SmallOrderFeeSettings({
    required this.isActive,
    required this.thresholdAmount,
    required this.feeAmount,
  });

  factory SmallOrderFeeSettings.fromJson(Map<String, dynamic> json) =>
      SmallOrderFeeSettings(
        isActive: json['is_active'] as bool? ?? true,
        thresholdAmount: (json['threshold_amount'] as num?)?.toInt() ?? 0,
        feeAmount: (json['fee_amount'] as num?)?.toInt() ?? 0,
      );

  /// Phí áp dụng cho 1 giỏ hàng có giá trị [subtotal] (đã gồm % mua hộ nếu có) — mirror đúng
  /// điều kiện phía server (create_order), chỉ để KHÁCH XEM TRƯỚC.
  int estimate(int subtotal) {
    if (!isActive) return 0;
    return subtotal < thresholdAmount ? feeAmount : 0;
  }
}
