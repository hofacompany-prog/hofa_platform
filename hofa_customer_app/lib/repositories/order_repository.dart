import '../core/api_client.dart';
import '../models/order.dart';
import '../models/delivery.dart';
import '../models/chat_message.dart';

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

  /// Tự đổi giờ hẹn giao của đơn giao ngay có đặt trước — xem Order.canEditScheduledFor,
  /// PATCH /orders/:id/scheduled-for. [scheduledFor] null để bỏ hẳn giờ hẹn, chuyển đơn về giao
  /// ngay bình thường (không thể hoàn tác, xem nút "Giao ngay" trên order_detail_screen.dart).
  Future<Order> updateScheduledFor(String id, DateTime? scheduledFor) async =>
      Order.fromJson(
        await _api.patch(
              '/orders/$id/scheduled-for',
              body: {'scheduled_for': scheduledFor?.toUtc().toIso8601String()},
            )
            as Map<String, dynamic>,
      );

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

  // ---- Nhắn tin trong đơn — xem hofa-db/74_order_chat.sql ----

  /// Trả về (danh sách tin nhắn, mốc "đã đọc tới lúc nào" của ĐẦU BÊN KIA) — mốc này dùng hiện
  /// "Đã gửi"/"Đã xem" cho tin CỦA MÌNH ở chat_screen.dart, null nếu chưa xác định được đầu bên
  /// kia hoặc họ chưa từng mở màn chat.
  Future<(List<ChatMessage>, DateTime?)> chatMessages(
    String orderId,
    ChatChannel channel,
  ) async {
    final data =
        await _api.get(
              '/orders/$orderId/messages',
              query: {'channel': channel.apiValue},
            )
            as Map<String, dynamic>;
    final list = data['messages'] as List;
    final messages = list
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    final otherPartyLastReadAt = DateTime.tryParse(
      data['other_party_last_read_at']?.toString() ?? '',
    );
    return (messages, otherPartyLastReadAt);
  }

  Future<ChatMessage> sendChatMessage(
    String orderId,
    ChatChannel channel, {
    String? body,
    String? imageUrl,
  }) async => ChatMessage.fromJson(
    await _api.post(
          '/orders/$orderId/messages',
          body: {
            'channel': channel.apiValue,
            if (body != null && body.isNotEmpty) 'body': body,
            if (imageUrl != null) 'image_url': imageUrl,
          },
        )
        as Map<String, dynamic>,
  );

  Future<ChatSettings> chatSettings() async {
    final json = await _api.get('/chat-settings');
    return json == null
        ? ChatSettings.fallback()
        : ChatSettings.fromJson(json as Map<String, dynamic>);
  }

  /// {customer_driver: n, customer_merchant: n} — dùng hiện badge nhỏ ở nút nhắn tin, không
  /// cần mở màn chat mới biết có tin mới.
  Future<Map<String, int>> chatUnreadCounts(String orderId) async {
    final json =
        await _api.get('/orders/$orderId/messages/unread-counts')
            as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, (v as num).toInt()));
  }
}
