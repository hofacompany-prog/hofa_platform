import '../core/api_client.dart';
import '../models/order.dart';

class OrderRepository {
  final _api = ApiClient.instance;

  Future<List<Order>> listForMerchant(String merchantId, {String? status}) async {
    final list = await _api.get('/merchants/$merchantId/orders', query: {
      'limit': 100,
      if (status != null) 'status': status,
    }) as List;
    return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> get(String id) async => Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

  Future<Order> updateStatus(String id, String status, {String? note}) async =>
      Order.fromJson(await _api.patch('/orders/$id/status', body: {
        'status': status,
        if (note != null && note.isNotEmpty) 'note': note,
      }) as Map<String, dynamic>);
}
