/// Cấu hình tài chính tài xế toàn sàn — % HOFA cắt trên phí giao + thuế GTGT/TNCN (trừ thẳng
/// lên driver_fee, cùng công thức merchants — xem hofa-db/72_driver_tax_rates.sql) + hạn mức
/// COD, xem hofa-db/62_driver_wallet_ledger.sql.
class DriverFinanceSettings {
  final String? id;
  final double driverFeeCommissionRate;
  final double vatRate;
  final double pitRate;
  final int codDebtLimit;
  // % phí mua hộ (orders.buy_on_behalf_fee) tài xế được chia, áp dụng chung mọi tài xế — khác
  // bậc TÍNH phí mua hộ (merchant_fee_tiers, cấu hình riêng từng cửa hàng). Xem
  // hofa-db/79_driver_buy_on_behalf_fee_share.sql.
  final double buyOnBehalfFeeShareRate;
  // Số tiền tối thiểu 1 lần rút — chặn tài xế rút vặt (vd 1-2đ), xem
  // hofa-db/86_driver_min_withdrawal_amount.sql.
  final int minWithdrawalAmount;

  DriverFinanceSettings({
    this.id,
    required this.driverFeeCommissionRate,
    this.vatRate = 0,
    this.pitRate = 0,
    required this.codDebtLimit,
    this.buyOnBehalfFeeShareRate = 0,
    this.minWithdrawalAmount = 0,
  });

  factory DriverFinanceSettings.fromJson(Map<String, dynamic> json) =>
      DriverFinanceSettings(
        id: json['id'] as String?,
        // NUMERIC ở Postgres về qua node-postgres là String, không phải num.
        driverFeeCommissionRate:
            double.tryParse('${json['driver_fee_commission_rate']}') ?? 0,
        vatRate: double.tryParse('${json['vat_rate']}') ?? 0,
        pitRate: double.tryParse('${json['pit_rate']}') ?? 0,
        codDebtLimit: (json['cod_debt_limit'] as num?)?.toInt() ?? 2000000,
        buyOnBehalfFeeShareRate:
            double.tryParse('${json['buy_on_behalf_fee_share_rate']}') ?? 0,
        minWithdrawalAmount:
            (json['min_withdrawal_amount'] as num?)?.toInt() ?? 0,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory DriverFinanceSettings.fallback() =>
      DriverFinanceSettings(driverFeeCommissionRate: 0, codDebtLimit: 2000000);

  Map<String, dynamic> toJson() => {
    'driver_fee_commission_rate': driverFeeCommissionRate,
    'vat_rate': vatRate,
    'pit_rate': pitRate,
    'cod_debt_limit': codDebtLimit,
    'buy_on_behalf_fee_share_rate': buyOnBehalfFeeShareRate,
    'min_withdrawal_amount': minWithdrawalAmount,
  };
}
