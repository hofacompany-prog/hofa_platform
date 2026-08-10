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
  final String? driverId;
  final String? driverName;
  final num? driverRatingAvg;

  Delivery({
    required this.id,
    required this.orderId,
    required this.status,
    this.deliveryOtp,
    this.distanceKm,
    this.etaMinutes,
    this.driverId,
    this.driverName,
    this.driverRatingAvg,
  });

  factory Delivery.fromJson(Map<String, dynamic> json) => Delivery(
        id: json['id'] as String,
        orderId: json['order_id'] as String,
        status: json['status'] as String? ?? 'pending',
        deliveryOtp: json['delivery_otp'] as String?,
        distanceKm: json['distance_km'] != null ? num.tryParse('${json['distance_km']}') : null,
        etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
        driverId: json['driver_id'] as String?,
        driverName: json['driver_name'] as String?,
        driverRatingAvg: json['driver_rating_avg'] != null
            ? num.tryParse('${json['driver_rating_avg']}')
            : null,
      );
}
