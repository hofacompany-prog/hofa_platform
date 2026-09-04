const deliveryStatusLabels = {
  'pending': 'Đang tìm tài xế',
  'assigned': 'Đã gán tài xế — chờ xác nhận',
  'accepted': 'Tài xế đã nhận đơn',
  'arrived_store': 'Tài xế đã đến quán',
  'picked_up': 'Tài xế đã lấy hàng',
  'delivering': 'Đang giao tới bạn',
  'delivered': 'Đã giao xong',
  'failed': 'Giao thất bại',
  'returned': 'Đã trả hàng',
};

class Delivery {
  final String id;
  final String orderId;
  final String status;
  final String? deliveryOtp;
  final num? distanceKm;
  final int? etaMinutes;
  // ETA (phút) tài xế dự kiến TỚI CỬA HÀNG để lấy hàng, tính lúc gán — khác etaMinutes (ETA cả
  // chuyến cửa hàng→khách). Xem hofa-db/105_early_driver_search.sql.
  final int? pickupEtaMinutes;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final num? driverRatingAvg;

  Delivery({
    required this.id,
    required this.orderId,
    required this.status,
    this.deliveryOtp,
    this.distanceKm,
    this.etaMinutes,
    this.pickupEtaMinutes,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.driverRatingAvg,
  });

  factory Delivery.fromJson(Map<String, dynamic> json) => Delivery(
        id: json['id'] as String,
        orderId: json['order_id'] as String,
        status: json['status'] as String? ?? 'pending',
        deliveryOtp: json['delivery_otp'] as String?,
        distanceKm: json['distance_km'] != null ? num.tryParse('${json['distance_km']}') : null,
        etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
        pickupEtaMinutes: (json['pickup_eta_minutes'] as num?)?.toInt(),
        driverId: json['driver_id'] as String?,
        driverName: json['driver_name'] as String?,
        driverPhone: json['driver_phone'] as String?,
        driverRatingAvg: json['driver_rating_avg'] != null
            ? num.tryParse('${json['driver_rating_avg']}')
            : null,
      );
}
