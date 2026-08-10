/// 1 yêu cầu rút ví cửa hàng — xem GET /admin/merchant-wallet-withdrawals,
/// hofa-db/65_merchant_wallet_withdrawals.sql. bankBin thêm ở hofa-db/66_merchant_bank_bin.sql —
/// null với cửa hàng đã có bank_name từ trước migration 66 (chưa vào sửa hồ sơ qua dropdown lần
/// nào), khi đó không dựng được VietQR, chỉ hiện chữ.
class MerchantWalletRequest {
  final String id;
  final String merchantId;
  final String merchantName;
  final int amount;
  final String status;
  final DateTime createdAt;
  final String? rejectReason;
  final String? bankName;
  final String? bankBin;
  final String? bankAccountNo;
  final String? bankAccountName;

  MerchantWalletRequest({
    required this.id,
    required this.merchantId,
    required this.merchantName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.rejectReason,
    this.bankName,
    this.bankBin,
    this.bankAccountNo,
    this.bankAccountName,
  });

  factory MerchantWalletRequest.fromJson(Map<String, dynamic> json) =>
      MerchantWalletRequest(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        merchantName: json['merchant_name'] as String? ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'pending',
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        rejectReason: json['reject_reason'] as String?,
        bankName: json['bank_name'] as String?,
        bankBin: json['bank_bin'] as String?,
        bankAccountNo: json['bank_account_no'] as String?,
        bankAccountName: json['bank_account_name'] as String?,
      );
}
