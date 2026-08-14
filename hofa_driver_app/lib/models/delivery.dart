import '../core/format.dart';

const deliveryStatusLabels = {
  'pending': 'Đang tìm tài xế',
  'assigned': 'Đã gán — chờ xác nhận',
  'accepted': 'Đã nhận đơn',
  'arrived_store': 'Đã đến quán',
  'picked_up': 'Đã lấy hàng',
  'delivering': 'Đang giao',
  'delivered': 'Đã giao xong',
  'failed': 'Giao thất bại',
  'returned': 'Đã trả hàng',
};

class Delivery {
  final String id;
  final String orderId;
  final String? driverId;
  final String status;
  final String? branchName;
  final String? merchantName;
  final String? merchantType;
  final num? distanceKm;
  final int? etaMinutes;
  final int driverFee;
  // Chốt lúc giao xong (delivered), 0 nếu chưa giao xong — xem hofa-db/72_driver_tax_rates.sql.
  // driverPayout = driverFee - commissionAmount - vatAmount - pitAmount, đúng bằng số tiền
  // thực tế cộng vào ví.
  final int commissionAmount;
  final int vatAmount;
  final int pitAmount;
  final int driverPayout;
  final DateTime? assignedAt;
  final DateTime? acceptDeadline;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final String? pickupOtp;
  final String? deliveryOtp;
  final List<String> proofPhotoUrls;
  final String? failureReason;

  Delivery({
    required this.id,
    required this.orderId,
    this.driverId,
    required this.status,
    this.branchName,
    this.merchantName,
    this.merchantType,
    this.distanceKm,
    this.etaMinutes,
    required this.driverFee,
    this.commissionAmount = 0,
    this.vatAmount = 0,
    this.pitAmount = 0,
    this.driverPayout = 0,
    this.assignedAt,
    this.acceptDeadline,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.pickupOtp,
    this.deliveryOtp,
    this.proofPhotoUrls = const [],
    this.failureReason,
  });

  /// Tên quán trước, tên chi nhánh sau (null nếu chưa có branch_name — hiếm, chỉ khi lỗi join).
  String? get pickupDisplayName =>
      branchName == null ? null : pickupTitle(merchantName, branchName!);

  /// Đơn mua hộ — tài xế tự đi mua tại quán, không có OTP lấy hàng (xem delivery_detail_screen).
  bool get isBuyOnBehalf => merchantType == 'buy_on_behalf';

  factory Delivery.fromJson(Map<String, dynamic> json) => Delivery(
    id: json['id'] as String,
    orderId: json['order_id'] as String,
    driverId: json['driver_id'] as String?,
    status: json['status'] as String? ?? 'pending',
    branchName: json['branch_name'] as String?,
    merchantName: json['merchant_name'] as String?,
    merchantType: json['merchant_type'] as String?,
    distanceKm: json['distance_km'] != null
        ? num.tryParse('${json['distance_km']}')
        : null,
    etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
    driverFee: (json['driver_fee'] as num?)?.toInt() ?? 0,
    commissionAmount: (json['commission_amount'] as num?)?.toInt() ?? 0,
    vatAmount: (json['vat_amount'] as num?)?.toInt() ?? 0,
    pitAmount: (json['pit_amount'] as num?)?.toInt() ?? 0,
    driverPayout: (json['driver_payout'] as num?)?.toInt() ?? 0,
    assignedAt: json['assigned_at'] != null
        ? DateTime.tryParse(json['assigned_at'] as String)
        : null,
    acceptDeadline: json['accept_deadline'] != null
        ? DateTime.tryParse(json['accept_deadline'] as String)
        : null,
    acceptedAt: json['accepted_at'] != null
        ? DateTime.tryParse(json['accepted_at'] as String)
        : null,
    pickedUpAt: json['picked_up_at'] != null
        ? DateTime.tryParse(json['picked_up_at'] as String)
        : null,
    deliveredAt: json['delivered_at'] != null
        ? DateTime.tryParse(json['delivered_at'] as String)
        : null,
    pickupOtp: json['pickup_otp'] as String?,
    deliveryOtp: json['delivery_otp'] as String?,
    proofPhotoUrls: json['proof_photo_urls'] is List
        ? (json['proof_photo_urls'] as List).map((e) => e.toString()).toList()
        : const [],
    failureReason: json['failure_reason'] as String?,
  );
}
