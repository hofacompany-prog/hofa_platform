import '../core/api_client.dart';
import '../models/order.dart';
import '../models/delivery.dart';

class OrderRepository {
  final _api = ApiClient.instance;

  Future<Order> createOrder(Map<String, dynamic> data) async => Order.fromJson(
    await _api.post('/orders', body: data) as Map<String, dynamic>,
  );

  Future<List<Order>> myOrders({
    String? status,
    String? from,
    String? to,
    int limit = 50,
    int offset = 0,
  }) async {
    final list =
        await _api.get(
              '/orders/mine',
              query: {
                'limit': limit,
                'offset': offset,
                if (status != null) 'status': status,
                if (from != null) 'from': from,
                if (to != null) 'to': to,
              },
            )
            as List;
    return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> order(String id) async =>
      Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

  /// null nếu đơn chưa được gán tài xế (chưa tới lúc có mã giao hàng).
  Future<Delivery?> delivery(String orderId) async {
    final json =
        await _api.get('/orders/$orderId/delivery') as Map<String, dynamic>?;
    return json == null ? null : Delivery.fromJson(json);
  }

  Future<List<OrderStatusEvent>> history(String id) async {
    final list = await _api.get('/orders/$id/history') as List;
    return list
        .map((e) => OrderStatusEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Order> cancelOrder(String id, {String? note}) async => Order.fromJson(
    await _api.patch(
          '/orders/$id/status',
          body: {'status': 'cancelled', if (note != null) 'note': note},
        )
        as Map<String, dynamic>,
  );

  /// Chọn (hoặc chọn lại) tài xế cho đơn mua hộ — xem models/order.dart Order.needsDriverPick.
  Future<void> selectDriver(String orderId, String driverId) async {
    await _api.post(
      '/orders/$orderId/select-driver',
      body: {'driver_id': driverId},
    );
  }
}
