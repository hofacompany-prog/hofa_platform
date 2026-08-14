/// Cấu hình tài chính tài xế toàn sàn (admin cấu hình) — dùng để ƯỚC TÍNH khoản trừ hoa hồng/
/// thuế GTGT/TNCN trước khi chuyến giao xong (số thật chốt lúc giao xong, xem
/// hofa-db/72_driver_tax_rates.sql).
class DriverFinanceSettings {
  final double driverFeeCommissionRate;
  final double vatRate;
  final double pitRate;

  DriverFinanceSettings({
    required this.driverFeeCommissionRate,
    required this.vatRate,
    required this.pitRate,
  });

  factory DriverFinanceSettings.fromJson(Map<String, dynamic> json) =>
      DriverFinanceSettings(
        driverFeeCommissionRate:
            double.tryParse('${json['driver_fee_commission_rate']}') ?? 0,
        vatRate: double.tryParse('${json['vat_rate']}') ?? 0,
        pitRate: double.tryParse('${json['pit_rate']}') ?? 0,
      );

  factory DriverFinanceSettings.fallback() =>
      DriverFinanceSettings(driverFeeCommissionRate: 0, vatRate: 0, pitRate: 0);
}
