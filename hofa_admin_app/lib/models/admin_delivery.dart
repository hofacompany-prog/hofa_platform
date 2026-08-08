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
/// GET /admin/deliveries (danh sách) hoặc GET /admin/deliveries/:id (chi tiết, có thêm đầy đủ
/// điểm lấy hàng/giao hàng để sửa) — không phải map 1:1 cột bảng deliveries như phía driver app.
/// Các field chỉ có ở bản chi tiết (branch*/ship*/customerPhone) null khi lấy từ danh sách.
class AdminDelivery {
  final String id;
  final String orderId;
  final String orderCode;
  final String? merchantId;
  final String? merchantName;
  final String? customerName;
  final String? customerPhone;
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

  // Điểm giao hàng (orders.ship_*) — chỉ có ở bản chi tiết.
  final String? shipLine1;
  final String? shipWard;
  final String? shipDistrict;
  final String? shipProvince;
  final double? shipLatitude;
  final double? shipLongitude;

  // Điểm lấy hàng (branches.*) — chỉ có ở bản chi tiết.
  final String? branchId;
  final String? branchName;
  final String? branchPhone;
  final String? branchLine1;
  final String? branchWard;
  final String? branchDistrict;
  final String? branchProvince;
  final double? branchLatitude;
  final double? branchLongitude;

  AdminDelivery({
    required this.id,
    required this.orderId,
    required this.orderCode,
    this.merchantId,
    this.merchantName,
    this.customerName,
    this.customerPhone,
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
    this.shipLine1,
    this.shipWard,
    this.shipDistrict,
    this.shipProvince,
    this.shipLatitude,
    this.shipLongitude,
    this.branchId,
    this.branchName,
    this.branchPhone,
    this.branchLine1,
    this.branchWard,
    this.branchDistrict,
    this.branchProvince,
    this.branchLatitude,
    this.branchLongitude,
  });

  String get shipFullAddress =>
      [shipLine1, shipWard, shipDistrict, shipProvince].where((e) => e != null && e.isNotEmpty).join(', ');

  String get branchFullAddress =>
      [branchLine1, branchWard, branchDistrict, branchProvince].where((e) => e != null && e.isNotEmpty).join(', ');

  factory AdminDelivery.fromJson(Map<String, dynamic> json) => AdminDelivery(
        id: json['id'] as String,
        orderId: json['order_id'] as String,
        orderCode: json['order_code'] as String? ?? '',
        merchantId: json['merchant_id'] as String?,
        merchantName: json['merchant_name'] as String?,
        customerName: json['customer_name'] as String?,
        customerPhone: json['customer_phone'] as String?,
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
        shipLine1: json['ship_line1'] as String?,
        shipWard: json['ship_ward'] as String?,
        shipDistrict: json['ship_district'] as String?,
        shipProvince: json['ship_province'] as String?,
        shipLatitude: json['ship_latitude'] != null ? double.tryParse('${json['ship_latitude']}') : null,
        shipLongitude: json['ship_longitude'] != null ? double.tryParse('${json['ship_longitude']}') : null,
        branchId: json['branch_id'] as String?,
        branchName: json['branch_name'] as String?,
        branchPhone: json['branch_phone'] as String?,
        branchLine1: json['branch_line1'] as String?,
        branchWard: json['branch_ward'] as String?,
        branchDistrict: json['branch_district'] as String?,
        branchProvince: json['branch_province'] as String?,
        branchLatitude: json['branch_latitude'] != null ? double.tryParse('${json['branch_latitude']}') : null,
        branchLongitude: json['branch_longitude'] != null ? double.tryParse('${json['branch_longitude']}') : null,
      );
}
