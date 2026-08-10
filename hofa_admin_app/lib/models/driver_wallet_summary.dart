/// Số tổng toàn sàn cho dashboard "Ví tài xế" — xem GET /admin/driver-wallets/summary.
class DriverWalletSummary {
  final int codHeld;
  final int earningTotal;
  final int pendingWithdrawals;
  final int pendingSettlements;

  DriverWalletSummary({
    required this.codHeld,
    required this.earningTotal,
    required this.pendingWithdrawals,
    required this.pendingSettlements,
  });

  // SUM() trên cột INTEGER tự nâng kiểu lên BIGINT trong Postgres — node-postgres trả BIGINT
  // dưới dạng String (tránh mất độ chính xác với số lớn hơn 2^53), không phải num, nên phải
  // parse qua String thay vì ép kiểu num? trực tiếp (khác các cột INTEGER thường trả về num).
  factory DriverWalletSummary.fromJson(Map<String, dynamic> json) =>
      DriverWalletSummary(
        codHeld: int.tryParse('${json['cod_held']}') ?? 0,
        earningTotal: int.tryParse('${json['earning_total']}') ?? 0,
        pendingWithdrawals: int.tryParse('${json['pending_withdrawals']}') ?? 0,
        pendingSettlements: int.tryParse('${json['pending_settlements']}') ?? 0,
      );
}
