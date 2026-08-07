/// 1 bậc phí mua hộ của 1 cửa hàng (merchant_type = 'buy_on_behalf') — admin cấu hình ở màn
/// chi tiết cửa hàng, KHÁC wholesale_tiers (chủ cửa hàng tự cấu hình theo biến thể sản phẩm).
/// Ngưỡng (minThreshold/maxThreshold) tính theo số lượng sản phẩm hay giá trị đơn hàng tuỳ
/// merchants.buyOnBehalfFeeBasis. Mỗi bậc chọn 1 trong 2 cách tính phí: cố định (VNĐ) hoặc %.
class MerchantFeeTier {
  final String id;
  final String merchantId;
  final int minThreshold;
  final int? maxThreshold;
  final String feeType; // 'fixed' | 'percent'
  final int? feeFixedAmount;
  final num? feePercent;

  MerchantFeeTier({
    required this.id,
    required this.merchantId,
    required this.minThreshold,
    this.maxThreshold,
    required this.feeType,
    this.feeFixedAmount,
    this.feePercent,
  });

  bool get isFixed => feeType == 'fixed';

  factory MerchantFeeTier.fromJson(Map<String, dynamic> json) => MerchantFeeTier(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        minThreshold: (json['min_threshold'] as num?)?.toInt() ?? 0,
        maxThreshold: (json['max_threshold'] as num?)?.toInt(),
        feeType: json['fee_type'] as String? ?? 'fixed',
        feeFixedAmount: (json['fee_fixed_amount'] as num?)?.toInt(),
        feePercent: json['fee_percent'] != null ? num.tryParse('${json['fee_percent']}') : null,
      );
}

const buyOnBehalfFeeBasisLabels = {
  'quantity': 'Theo số lượng sản phẩm',
  'value': 'Theo giá trị đơn hàng',
};
