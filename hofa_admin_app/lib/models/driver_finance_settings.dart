/// Cấu hình tài chính tài xế toàn sàn — % HOFA cắt trên phí giao + hạn mức COD, xem
/// hofa-db/62_driver_wallet_ledger.sql.
class DriverFinanceSettings {
  final String? id;
  final double driverFeeCommissionRate;
  final int codDebtLimit;

  DriverFinanceSettings({
    this.id,
    required this.driverFeeCommissionRate,
    required this.codDebtLimit,
  });

  factory DriverFinanceSettings.fromJson(Map<String, dynamic> json) =>
      DriverFinanceSettings(
        id: json['id'] as String?,
        // NUMERIC ở Postgres về qua node-postgres là String, không phải num.
        driverFeeCommissionRate:
            double.tryParse('${json['driver_fee_commission_rate']}') ?? 0,
        codDebtLimit: (json['cod_debt_limit'] as num?)?.toInt() ?? 2000000,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory DriverFinanceSettings.fallback() =>
      DriverFinanceSettings(driverFeeCommissionRate: 0, codDebtLimit: 2000000);

  Map<String, dynamic> toJson() => {
    'driver_fee_commission_rate': driverFeeCommissionRate,
    'cod_debt_limit': codDebtLimit,
  };
}
