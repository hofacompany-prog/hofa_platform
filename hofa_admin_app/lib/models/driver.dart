class Driver {
  final String id;
  final String userId;
  // Thông tin người dùng (bảng users, JOIN sẵn ở GET /admin/drivers, /admin/drivers/:id) — null
  // ở những response cũ/khác chưa JOIN (vd response của các action verify/reject/updateDriver
  // chỉ trả nguyên dòng drivers).
  final String? fullName;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final String? userStatus;
  final String? nationalId;
  final String? licenseNo;
  final DateTime? licenseExpiry;
  final String? vehicleType;
  final String? vehiclePlate;
  final num? vehicleCapacityKg;
  final List<String> documentUrls;
  final String status;
  final bool autoAccept;
  // Thuộc nhóm "Tài xế dự phòng" — nhận không giới hạn đơn cùng lúc, chỉ được mời khi không tìm
  // được tài xế thường nào (xem drivers_screen.dart, server/src/dispatch.js).
  final bool isBackupDriver;
  final double? currentLatitude;
  final double? currentLongitude;
  final DateTime? locationUpdatedAt;
  final int walletBalance;
  // Ví COD (tiền đang giữ hộ, chưa nộp lại HOFA) + ví thu nhập (rút được) — tính động từ
  // driver_wallet_transactions, xem hofa-db/62_driver_wallet_ledger.sql. walletBalance ở trên
  // KHÔNG CÒN DÙNG (deprecated), giữ lại field chỉ để không phá model cũ.
  final int codBalance;
  final int earningBalance;
  final int totalDeliveries;
  final num ratingAvg;
  final int ratingCount;
  final DateTime? verifiedAt;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final String? bankName;
  final String? bankBin;
  final String? bankAccountNumber;
  final String? bankAccountHolder;
  final DateTime? createdAt;

  Driver({
    required this.id,
    required this.userId,
    this.fullName,
    this.phone,
    this.email,
    this.avatarUrl,
    this.userStatus,
    this.nationalId,
    this.licenseNo,
    this.licenseExpiry,
    this.vehicleType,
    this.vehiclePlate,
    this.vehicleCapacityKg,
    this.documentUrls = const [],
    required this.status,
    this.autoAccept = false,
    this.isBackupDriver = false,
    this.currentLatitude,
    this.currentLongitude,
    this.locationUpdatedAt,
    required this.walletBalance,
    this.codBalance = 0,
    this.earningBalance = 0,
    required this.totalDeliveries,
    required this.ratingAvg,
    this.ratingCount = 0,
    this.verifiedAt,
    this.rejectedAt,
    this.rejectionReason,
    this.bankName,
    this.bankBin,
    this.bankAccountNumber,
    this.bankAccountHolder,
    this.createdAt,
  });

  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
    id: j['id'] as String,
    userId: j['user_id'] as String,
    fullName: j['full_name'] as String?,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    avatarUrl: j['avatar_url'] as String?,
    userStatus: j['user_status'] as String?,
    nationalId: j['national_id'] as String?,
    licenseNo: j['license_no'] as String?,
    licenseExpiry: j['license_expiry'] != null
        ? DateTime.tryParse(j['license_expiry'].toString())
        : null,
    vehicleType: j['vehicle_type'] as String?,
    vehiclePlate: j['vehicle_plate'] as String?,
    vehicleCapacityKg: j['vehicle_capacity_kg'] != null
        ? num.tryParse('${j['vehicle_capacity_kg']}')
        : null,
    documentUrls: j['document_urls'] is List
        ? (j['document_urls'] as List).map((e) => e.toString()).toList()
        : const [],
    status: j['status'] as String? ?? 'offline',
    autoAccept: j['auto_accept'] as bool? ?? false,
    isBackupDriver: j['is_backup_driver'] as bool? ?? false,
    currentLatitude: j['current_latitude'] != null
        ? double.tryParse('${j['current_latitude']}')
        : null,
    currentLongitude: j['current_longitude'] != null
        ? double.tryParse('${j['current_longitude']}')
        : null,
    locationUpdatedAt: j['location_updated_at'] != null
        ? DateTime.tryParse(j['location_updated_at'].toString())
        : null,
    walletBalance: (j['wallet_balance'] as num?)?.toInt() ?? 0,
    codBalance: (j['cod_balance'] as num?)?.toInt() ?? 0,
    earningBalance: (j['earning_balance'] as num?)?.toInt() ?? 0,
    totalDeliveries: (j['total_deliveries'] as num?)?.toInt() ?? 0,
    ratingAvg: num.tryParse('${j['rating_avg']}') ?? 0,
    ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
    verifiedAt: DateTime.tryParse(j['verified_at']?.toString() ?? ''),
    rejectedAt: DateTime.tryParse(j['rejected_at']?.toString() ?? ''),
    rejectionReason: j['rejection_reason'] as String?,
    bankName: j['bank_name'] as String?,
    bankBin: j['bank_bin'] as String?,
    bankAccountNumber: j['bank_account_number'] as String?,
    bankAccountHolder: j['bank_account_holder'] as String?,
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
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
