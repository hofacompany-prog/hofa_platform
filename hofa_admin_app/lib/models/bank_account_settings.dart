/// Thông tin tài khoản ngân hàng của sàn — dùng tạo mã VietQR cho khách quét chuyển khoản.
class BankAccountSettings {
  final String? id;
  final String? bankName;
  final String? bankBin;
  final String? accountNumber;
  final String? accountHolderName;

  BankAccountSettings({
    this.id,
    this.bankName,
    this.bankBin,
    this.accountNumber,
    this.accountHolderName,
  });

  bool get isConfigured =>
      (bankBin != null && bankBin!.isNotEmpty) && (accountNumber != null && accountNumber!.isNotEmpty);

  factory BankAccountSettings.fromJson(Map<String, dynamic> json) => BankAccountSettings(
        id: json['id'] as String?,
        bankName: json['bank_name'] as String?,
        bankBin: json['bank_bin'] as String?,
        accountNumber: json['account_number'] as String?,
        accountHolderName: json['account_holder_name'] as String?,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory BankAccountSettings.fallback() => BankAccountSettings();

  Map<String, dynamic> toJson() => {
        'bank_name': bankName,
        'bank_bin': bankBin,
        'account_number': accountNumber,
        'account_holder_name': accountHolderName,
      };
}
