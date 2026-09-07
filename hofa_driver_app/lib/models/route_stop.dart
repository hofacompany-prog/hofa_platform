/// 1 điểm dừng (lấy hàng hoặc giao hàng) trong lộ trình đã sắp xếp tối ưu cho toàn bộ chuyến
/// đang chạy của tài xế — xem GET /deliveries/mine/route (server/src/routes/deliveries.js),
/// tái dùng đúng thuật toán quyết định ghép đơn (server/src/batchDispatch.js#bestRoutePath).
class RouteStop {
  final String deliveryId;
  final String orderId;
  final bool isPickup;

  RouteStop({
    required this.deliveryId,
    required this.orderId,
    required this.isPickup,
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) => RouteStop(
    deliveryId: json['delivery_id'] as String,
    orderId: json['order_id'] as String,
    isPickup: json['type'] == 'pickup',
  );
}
