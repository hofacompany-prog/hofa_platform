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
      );

  bool get isVerified => verifiedAt != null;
}

const driverStatusLabels = {
  'offline': 'Ngoại tuyến',
  'online': 'Sẵn sàng',
  'busy': 'Đang giao',
  'on_break': 'Nghỉ giữa ca',
};
