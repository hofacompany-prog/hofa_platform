/// Thông tin tài khoản ngân hàng CỦA SÀN — dùng dựng QR để tài xế nạp tiền vào ví, và đọc
/// min_withdrawal_balance để hiện hạn mức rút. Chỉ đọc (admin mới sửa được).
class BankAccountSettings {
  final String? bankName;
  final String? bankBin;
  final String? accountNumber;
  final String? accountHolderName;
  final int minWithdrawalBalance;

  BankAccountSettings({
    this.bankName,
    this.bankBin,
    this.accountNumber,
    this.accountHolderName,
    this.minWithdrawalBalance = 0,
  });

  bool get isConfigured =>
      (bankBin != null && bankBin!.isNotEmpty) && (accountNumber != null && accountNumber!.isNotEmpty);

  factory BankAccountSettings.fromJson(Map<String, dynamic> json) => BankAccountSettings(
        bankName: json['bank_name'] as String?,
        bankBin: json['bank_bin'] as String?,
        accountNumber: json['account_number'] as String?,
        accountHolderName: json['account_holder_name'] as String?,
        minWithdrawalBalance: (json['min_withdrawal_balance'] as num?)?.toInt() ?? 0,
      );

  factory BankAccountSettings.empty() => BankAccountSettings();
}
