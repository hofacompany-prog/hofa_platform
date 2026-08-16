/// Cách tính ngưỡng bậc phí mua hộ mặc định toàn sàn — chỉ 1 dòng đang áp dụng (giống
/// [ShippingFeeSettings]/voucher_settings), admin sửa ở màn Tài chính > Phí mua hộ. Dùng làm
/// khuôn copy sang merchants.buyOnBehalfFeeBasis + merchant_fee_tiers cho MỖI cửa hàng
/// merchant_type='buy_on_behalf' MỚI TẠO — sửa ở đây không ảnh hưởng cửa hàng đã có sẵn.
class PlatformFeeSettings {
  final String? id;
  final String feeBasis; // 'quantity' | 'value'

  PlatformFeeSettings({this.id, required this.feeBasis});

  factory PlatformFeeSettings.fromJson(Map<String, dynamic> json) =>
      PlatformFeeSettings(
        id: json['id'] as String?,
        feeBasis: json['fee_basis'] as String? ?? 'value',
      );
}

/// 1 bậc phí mua hộ mặc định toàn sàn — cùng hình dạng với MerchantFeeTier nhưng không gắn
/// vào 1 cửa hàng cụ thể nào (không có merchantId).
class PlatformFeeTier {
  final String id;
  final int minThreshold;
  final int? maxThreshold;
  final String feeType; // 'fixed' | 'percent'
  final int? feeFixedAmount;
  final num? feePercent;

  PlatformFeeTier({
    required this.id,
    required this.minThreshold,
    this.maxThreshold,
    required this.feeType,
    this.feeFixedAmount,
    this.feePercent,
  });

  bool get isFixed => feeType == 'fixed';

  factory PlatformFeeTier.fromJson(Map<String, dynamic> json) =>
      PlatformFeeTier(
        id: json['id'] as String,
        minThreshold: (json['min_threshold'] as num?)?.toInt() ?? 0,
        maxThreshold: (json['max_threshold'] as num?)?.toInt(),
        feeType: json['fee_type'] as String? ?? 'fixed',
        feeFixedAmount: (json['fee_fixed_amount'] as num?)?.toInt(),
        feePercent: json['fee_percent'] != null
            ? num.tryParse('${json['fee_percent']}')
            : null,
      );
}

/// Gộp settings + danh sách bậc trong 1 lần gọi (GET /platform-fee-settings trả về cả 2).
class PlatformFeeData {
  final PlatformFeeSettings settings;
  final List<PlatformFeeTier> tiers;

  PlatformFeeData({required this.settings, required this.tiers});

  factory PlatformFeeData.fromJson(Map<String, dynamic> json) =>
      PlatformFeeData(
        settings: PlatformFeeSettings.fromJson(
          json['settings'] as Map<String, dynamic>? ?? const {},
        ),
        tiers: ((json['tiers'] as List?) ?? const [])
            .map((e) => PlatformFeeTier.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
