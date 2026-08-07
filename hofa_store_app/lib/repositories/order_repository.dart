import '../core/api_client.dart';
import '../models/order.dart';
import '../models/delivery.dart';

class OrderRepository {
  final _api = ApiClient.instance;

  /// null nếu đơn chưa được gán tài xế (chưa tới lúc có mã lấy hàng).
  Future<Delivery?> delivery(String orderId) async {
    final json = await _api.get('/orders/$orderId/delivery') as Map<String, dynamic>?;
    return json == null ? null : Delivery.fromJson(json);
  }

  Future<List<Order>> listForMerchant(
    String merchantId, {
    String? status,
    String? from,
    String? to,
  }) async {
    final list = await _api.get('/merchants/$merchantId/orders', query: {
      'limit': 100,
      if (status != null) 'status': status,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    }) as List;
    return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> get(String id) async => Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

  Future<Order> updateStatus(String id, String status, {String? note}) async =>
      Order.fromJson(await _api.patch('/orders/$id/status', body: {
        'status': status,
        if (note != null && note.isNotEmpty) 'note': note,
      }) as Map<String, dynamic>);

  /// Thử lại tìm tài xế online gần nhất — dùng khi đơn đã "Chờ tài xế lấy" nhưng
  /// lần tự động đầu (lúc chuyển trạng thái) không tìm thấy ai (chưa có tài xế online).
  Future<void> findDriver(String orderId) async {
    await _api.post('/orders/$orderId/find-driver');
  }
}
