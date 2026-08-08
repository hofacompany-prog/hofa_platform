/// Nhãn tiếng Việt cho delivery_status (khớp enum trong 01_schema.sql).
const deliveryStatusLabels = {
  'pending': 'Đang tìm tài xế',
  'assigned': 'Đã gán — chờ xác nhận',
  'accepted': 'Đã nhận',
  'arrived_store': 'Đã đến quán',
  'picked_up': 'Đã lấy hàng',
  'delivering': 'Đang giao',
  'delivered': 'Đã giao xong',
  'failed': 'Giao thất bại',
  'returned': 'Đã trả hàng',
};

/// Các trạng thái coi là "đang hoạt động" — khớp ACTIVE_DELIVERY_STATUSES phía server
/// (deliveries.js), dùng làm bộ lọc mặc định của màn giám sát chuyến giao hàng.
const activeDeliveryStatuses = ['pending', 'assigned', 'accepted', 'arrived_store', 'picked_up', 'delivering'];

/// Chuyến giao hàng nhìn từ phía admin — gộp sẵn tên tài xế/mã đơn/cửa hàng/khách qua JOIN ở
/// GET /admin/deliveries, không phải map 1:1 cột bảng deliveries như phía driver app.
class AdminDelivery {
  final String id;
  final String orderId;
  final String orderCode;
  final String? merchantName;
  final String? customerName;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final String status;
  final num? distanceKm;
  final int? etaMinutes;
  final int driverFee;
  final DateTime? assignedAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;

  AdminDelivery({
    required this.id,
    required this.orderId,
    required this.orderCode,
    this.merchantName,
    this.customerName,
    this.driverId,
    this.driverName,
    this.driverPhone,
    required this.status,
    this.distanceKm,
    this.etaMinutes,
    required this.driverFee,
    this.assignedAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
    required this.createdAt,
  });

  factory AdminDelivery.fromJson(Map<String, dynamic> json) => AdminDelivery(
        id: json['id'] as String,
        orderId: json['order_id'] as String,
        orderCode: json['order_code'] as String? ?? '',
        merchantName: json['merchant_name'] as String?,
        customerName: json['customer_name'] as String?,
        driverId: json['driver_id'] as String?,
        driverName: json['driver_name'] as String?,
        driverPhone: json['driver_phone'] as String?,
        status: json['status'] as String? ?? 'pending',
        distanceKm: json['distance_km'] != null ? num.tryParse('${json['distance_km']}') : null,
        etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
        driverFee: (json['driver_fee'] as num?)?.toInt() ?? 0,
        assignedAt: json['assigned_at'] != null ? DateTime.tryParse(json['assigned_at'].toString()) : null,
        acceptedAt: json['accepted_at'] != null ? DateTime.tryParse(json['accepted_at'].toString()) : null,
        pickedUpAt: json['picked_up_at'] != null ? DateTime.tryParse(json['picked_up_at'].toString()) : null,
        deliveredAt: json['delivered_at'] != null ? DateTime.tryParse(json['delivered_at'].toString()) : null,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}
