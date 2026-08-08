/// Thông tin tài khoản ngân hàng của sàn — dùng dựng URL ảnh VietQR ở màn chi tiết đơn cho
/// đơn thanh toán bằng chuyển khoản. Chỉ đọc (admin mới sửa được, xem hofa_admin_app).
class BankAccountSettings {
  final String? bankName;
  final String? bankBin;
  final String? accountNumber;
  final String? accountHolderName;

  BankAccountSettings({
    this.bankName,
    this.bankBin,
    this.accountNumber,
    this.accountHolderName,
  });

  bool get isConfigured =>
      (bankBin != null && bankBin!.isNotEmpty) && (accountNumber != null && accountNumber!.isNotEmpty);

  factory BankAccountSettings.fromJson(Map<String, dynamic> json) => BankAccountSettings(
        bankName: json['bank_name'] as String?,
        bankBin: json['bank_bin'] as String?,
        accountNumber: json['account_number'] as String?,
        accountHolderName: json['account_holder_name'] as String?,
      );

  factory BankAccountSettings.empty() => BankAccountSettings();
}
