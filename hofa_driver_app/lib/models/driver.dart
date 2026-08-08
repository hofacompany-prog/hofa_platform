class Driver {
  final String id;
  final String userId;
  final String? nationalId;
  final String? licenseNo;
  final String? vehicleType;
  final String? vehiclePlate;
  final List<String> documentUrls;
  final String status; // offline | online | busy | on_break
  final bool autoAccept;
  final double? currentLatitude;
  final double? currentLongitude;
  final int walletBalance;
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

  Driver({
    required this.id,
    required this.userId,
    this.nationalId,
    this.licenseNo,
    this.vehicleType,
    this.vehiclePlate,
    this.documentUrls = const [],
    required this.status,
    required this.autoAccept,
    this.currentLatitude,
    this.currentLongitude,
    required this.walletBalance,
    required this.totalDeliveries,
    required this.ratingAvg,
    required this.ratingCount,
    this.verifiedAt,
    this.rejectedAt,
    this.rejectionReason,
    this.bankName,
    this.bankBin,
    this.bankAccountNumber,
    this.bankAccountHolder,
  });

  bool get isVerified => verifiedAt != null;
  bool get isRejected => rejectedAt != null && verifiedAt == null;
  bool get isOnline => status == 'online' || status == 'busy';
  bool get hasBankInfo => (bankBin?.isNotEmpty ?? false) && (bankAccountNumber?.isNotEmpty ?? false);

  factory Driver.fromJson(Map<String, dynamic> json) => Driver(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        nationalId: json['national_id'] as String?,
        licenseNo: json['license_no'] as String?,
        vehicleType: json['vehicle_type'] as String?,
        vehiclePlate: json['vehicle_plate'] as String?,
        documentUrls:
            json['document_urls'] is List ? (json['document_urls'] as List).map((e) => e.toString()).toList() : const [],
        status: json['status'] as String? ?? 'offline',
        autoAccept: json['auto_accept'] as bool? ?? false,
        currentLatitude: double.tryParse('${json['current_latitude']}'),
        currentLongitude: double.tryParse('${json['current_longitude']}'),
        walletBalance: (json['wallet_balance'] as num?)?.toInt() ?? 0,
        totalDeliveries: (json['total_deliveries'] as num?)?.toInt() ?? 0,
        ratingAvg: num.tryParse('${json['rating_avg']}') ?? 0,
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
        verifiedAt: json['verified_at'] != null ? DateTime.tryParse(json['verified_at'] as String) : null,
        rejectedAt: json['rejected_at'] != null ? DateTime.tryParse(json['rejected_at'] as String) : null,
        rejectionReason: json['rejection_reason'] as String?,
        bankName: json['bank_name'] as String?,
        bankBin: json['bank_bin'] as String?,
        bankAccountNumber: json['bank_account_number'] as String?,
        bankAccountHolder: json['bank_account_holder'] as String?,
      );
}
