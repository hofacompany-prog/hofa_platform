import '../core/api_client.dart';
import '../models/order.dart';
import '../models/delivery.dart';

class OrderRepository {
  final _api = ApiClient.instance;

  Future<Order> createOrder(Map<String, dynamic> data) async =>
      Order.fromJson(await _api.post('/orders', body: data) as Map<String, dynamic>);

  Future<List<Order>> myOrders({String? status, int limit = 50}) async {
    final list = await _api.get('/orders/mine', query: {
      'limit': limit,
      if (status != null) 'status': status,
    }) as List;
    return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> order(String id) async => Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

  /// null nếu đơn chưa được gán tài xế (chưa tới lúc có mã giao hàng).
  Future<Delivery?> delivery(String orderId) async {
    final json = await _api.get('/orders/$orderId/delivery') as Map<String, dynamic>?;
    return json == null ? null : Delivery.fromJson(json);
  }

  Future<List<OrderStatusEvent>> history(String id) async {
    final list = await _api.get('/orders/$id/history') as List;
    return list.map((e) => OrderStatusEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> cancelOrder(String id, {String? note}) async => Order.fromJson(await _api.patch('/orders/$id/status', body: {
        'status': 'cancelled',
        if (note != null) 'note': note,
      }) as Map<String, dynamic>);
}
