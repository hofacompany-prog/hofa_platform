/// 1 bậc phí mua hộ của 1 cửa hàng (merchant.merchantType == 'buy_on_behalf') — admin cấu
/// hình ở web admin. Ngưỡng (minThreshold/maxThreshold) tính theo số lượng sản phẩm hay giá
/// trị đơn hàng tuỳ merchant.buyOnBehalfFeeBasis. Dùng để hiển thị bảng phí + ước tính phí ở
/// màn sản phẩm/thanh toán — số thật do server tự tính lại lúc tạo đơn (create_order), xem
/// hofa-db/28_merchant_buy_on_behalf.sql, không tin số ước tính ở đây.
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

/// Bậc có min_threshold cao nhất còn thoả [value] (số lượng hoặc giá trị đơn tuỳ basis) —
/// mirror đúng cách chọn bậc phía server trong create_order(). Trả về null nếu chưa đạt
/// bậc nào (phí = 0).
MerchantFeeTier? matchBuyOnBehalfTier(List<MerchantFeeTier> tiers, int value) {
  final candidates = tiers.where(
    (t) => t.minThreshold <= value && (t.maxThreshold == null || t.maxThreshold! >= value),
  ).toList()
    ..sort((a, b) => b.minThreshold.compareTo(a.minThreshold));
  return candidates.isEmpty ? null : candidates.first;
}

/// Số tiền phí mua hộ ước tính cho 1 bậc đã chọn — [subtotal] dùng khi bậc tính theo %.
int estimateBuyOnBehalfFee(MerchantFeeTier? tier, int subtotal) {
  if (tier == null) return 0;
  if (tier.isFixed) return tier.feeFixedAmount ?? 0;
  return ((subtotal * (tier.feePercent ?? 0)) / 100).round();
}

const buyOnBehalfFeeBasisLabels = {
  'quantity': 'Theo số lượng sản phẩm',
  'value': 'Theo giá trị đơn hàng',
};
