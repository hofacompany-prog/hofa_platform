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

  factory DriverWalletSummary.fromJson(Map<String, dynamic> json) =>
      DriverWalletSummary(
        codHeld: (json['cod_held'] as num?)?.toInt() ?? 0,
        earningTotal: (json['earning_total'] as num?)?.toInt() ?? 0,
        pendingWithdrawals: (json['pending_withdrawals'] as num?)?.toInt() ?? 0,
        pendingSettlements: (json['pending_settlements'] as num?)?.toInt() ?? 0,
      );
}
