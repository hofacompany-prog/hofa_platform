/// Số tổng toàn sàn cho dashboard "Ví cửa hàng" — xem GET /admin/merchant-wallets/summary.
class MerchantWalletSummary {
  final int totalBalance;
  final int pendingWithdrawals;

  MerchantWalletSummary({
    required this.totalBalance,
    required this.pendingWithdrawals,
  });

  // SUM() trên cột INTEGER tự nâng kiểu lên BIGINT trong Postgres — node-postgres trả BIGINT
  // dưới dạng String, không phải num (xem driver_wallet_summary.dart cùng lỗi đã vá trước đó).
  factory MerchantWalletSummary.fromJson(Map<String, dynamic> json) =>
      MerchantWalletSummary(
        totalBalance: int.tryParse('${json['total_balance']}') ?? 0,
        pendingWithdrawals: int.tryParse('${json['pending_withdrawals']}') ?? 0,
      );
}

/// 1 dòng trong bảng "Từng cửa hàng" — xem GET /admin/merchant-wallets.
class MerchantWalletBalance {
  final String id;
  final String name;
  final int balance;

  MerchantWalletBalance({
    required this.id,
    required this.name,
    required this.balance,
  });

  factory MerchantWalletBalance.fromJson(Map<String, dynamic> json) =>
      MerchantWalletBalance(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        balance: (json['balance'] as num?)?.toInt() ?? 0,
      );
}
