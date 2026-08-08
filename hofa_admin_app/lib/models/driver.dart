class Driver {
  final String id;
  final String userId;
  final String? nationalId;
  final String? licenseNo;
  final String? vehicleType;
  final String? vehiclePlate;
  final String status;
  final int walletBalance;
  final int totalDeliveries;
  final num ratingAvg;
  final DateTime? verifiedAt;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final String? bankName;
  final String? bankBin;
  final String? bankAccountNumber;
  final String? bankAccountHolder;

  Driver({
    required this.id,
    required this.userId,
    this.nationalId,
    this.licenseNo,
    this.vehicleType,
    this.vehiclePlate,
    required this.status,
    required this.walletBalance,
    required this.totalDeliveries,
    required this.ratingAvg,
    this.verifiedAt,
    this.rejectedAt,
    this.rejectionReason,
    this.bankName,
    this.bankBin,
    this.bankAccountNumber,
    this.bankAccountHolder,
  });

  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        nationalId: j['national_id'] as String?,
        licenseNo: j['license_no'] as String?,
        vehicleType: j['vehicle_type'] as String?,
        vehiclePlate: j['vehicle_plate'] as String?,
        status: j['status'] as String? ?? 'offline',
        walletBalance: (j['wallet_balance'] as num?)?.toInt() ?? 0,
        totalDeliveries: (j['total_deliveries'] as num?)?.toInt() ?? 0,
        ratingAvg: num.tryParse('${j['rating_avg']}') ?? 0,
        verifiedAt: DateTime.tryParse(j['verified_at']?.toString() ?? ''),
        rejectedAt: DateTime.tryParse(j['rejected_at']?.toString() ?? ''),
        rejectionReason: j['rejection_reason'] as String?,
        bankName: j['bank_name'] as String?,
        bankBin: j['bank_bin'] as String?,
        bankAccountNumber: j['bank_account_number'] as String?,
        bankAccountHolder: j['bank_account_holder'] as String?,
      );

  bool get isVerified => verifiedAt != null;
  bool get isRejected => rejectedAt != null && verifiedAt == null;
}

/// 3 trạng thái xét duyệt hồ sơ tài xế — verified_at/rejected_at trên bảng drivers.
enum DriverVerificationState { pending, verified, rejected }

DriverVerificationState driverVerificationState(Driver d) {
  if (d.isVerified) return DriverVerificationState.verified;
  if (d.isRejected) return DriverVerificationState.rejected;
  return DriverVerificationState.pending;
}

const driverStatusLabels = {
  'offline': 'Ngoại tuyến',
  'online': 'Sẵn sàng',
  'busy': 'Đang giao',
  'on_break': 'Nghỉ giữa ca',
};
