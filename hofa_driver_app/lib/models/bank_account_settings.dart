/// Thông tin tài khoản ngân hàng CỦA SÀN — đọc min_withdrawal_balance để hiện hạn mức rút, và
/// supportPhone để mở gọi/SMS/Zalo lúc tài xế bấm "Nạp tiền" (không còn hiện QR chuyển khoản
/// trực tiếp trong app, xem earnings_screen.dart). Chỉ đọc (admin mới sửa được).
class BankAccountSettings {
  final String? bankName;
  final String? bankBin;
  final String? accountNumber;
  final String? accountHolderName;
  final int minWithdrawalBalance;
  final String? supportPhone;

  BankAccountSettings({
    this.bankName,
    this.bankBin,
    this.accountNumber,
    this.accountHolderName,
    this.minWithdrawalBalance = 0,
    this.supportPhone,
  });

  bool get isConfigured =>
      (bankBin != null && bankBin!.isNotEmpty) && (accountNumber != null && accountNumber!.isNotEmpty);

  bool get hasSupportPhone => supportPhone != null && supportPhone!.trim().isNotEmpty;

  factory BankAccountSettings.fromJson(Map<String, dynamic> json) => BankAccountSettings(
        bankName: json['bank_name'] as String?,
        bankBin: json['bank_bin'] as String?,
        accountNumber: json['account_number'] as String?,
        accountHolderName: json['account_holder_name'] as String?,
        minWithdrawalBalance: (json['min_withdrawal_balance'] as num?)?.toInt() ?? 0,
        supportPhone: json['support_phone'] as String?,
      );

  factory BankAccountSettings.empty() => BankAccountSettings();
}
