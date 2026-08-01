import '../core/api_client.dart';
import '../models/order.dart';

class OrderRepository {
  final _api = ApiClient.instance;

  Future<Order> get(String id) async => Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);
}
