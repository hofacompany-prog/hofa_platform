/// 1 yêu cầu nạp hoặc rút ví tài xế — dùng chung shape cho cả GET /admin/wallet-deposits và
/// GET /admin/wallet-withdrawals; các trường ngân hàng chỉ có giá trị ở yêu cầu rút (admin cần
/// để tạo QR chuyển khoản trả tài xế).
class DriverWalletRequest {
  final String id;
  final String driverId;
  final String driverName;
  final String? driverPhone;
  final int amount;
  final String status;
  final DateTime createdAt;
  final String? rejectReason;
  final String? bankName;
  final String? bankBin;
  final String? bankAccountNumber;
  final String? bankAccountHolder;

  DriverWalletRequest({
    required this.id,
    required this.driverId,
    required this.driverName,
    this.driverPhone,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.rejectReason,
    this.bankName,
    this.bankBin,
    this.bankAccountNumber,
    this.bankAccountHolder,
  });

  factory DriverWalletRequest.fromJson(Map<String, dynamic> json) => DriverWalletRequest(
        id: json['id'] as String,
        driverId: json['driver_id'] as String,
        driverName: json['driver_name'] as String? ?? '',
        driverPhone: json['driver_phone'] as String?,
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'pending',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
        rejectReason: json['reject_reason'] as String?,
        bankName: json['bank_name'] as String?,
        bankBin: json['bank_bin'] as String?,
        bankAccountNumber: json['bank_account_number'] as String?,
        bankAccountHolder: json['bank_account_holder'] as String?,
      );
}
