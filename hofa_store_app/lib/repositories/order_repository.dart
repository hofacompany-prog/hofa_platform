import '../core/api_client.dart';
import '../models/order.dart';
import '../models/delivery.dart';
import '../models/chat_message.dart';

class OrderRepository {
  final _api = ApiClient.instance;

  /// null nếu đơn chưa được gán tài xế (chưa tới lúc có mã lấy hàng).
  Future<Delivery?> delivery(String orderId) async {
    final json =
        await _api.get('/orders/$orderId/delivery') as Map<String, dynamic>?;
    return json == null ? null : Delivery.fromJson(json);
  }

  Future<List<Order>> listForMerchant(
    String merchantId, {
    String? status,
    String? from,
    String? to,
    bool payoutOnly = false,
  }) async {
    final list =
        await _api.get(
              '/merchants/$merchantId/orders',
              query: {
                'limit': 100,
                if (status != null) 'status': status,
                if (from != null) 'from': from,
                if (to != null) 'to': to,
                if (payoutOnly) 'payout_only': 'true',
              },
            )
            as List;
    return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> get(String id) async =>
      Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

  Future<Order> updateStatus(
    String id,
    String status, {
    String? note,
    int? estimatedPrepMinutes,
  }) async => Order.fromJson(
    await _api.patch(
          '/orders/$id/status',
          body: {
            'status': status,
            if (note != null && note.isNotEmpty) 'note': note,
            if (estimatedPrepMinutes != null)
              'estimated_prep_minutes': estimatedPrepMinutes,
          },
        )
        as Map<String, dynamic>,
  );

  /// Thử lại tìm tài xế online gần nhất — dùng khi đơn đã "Chờ tài xế lấy" nhưng
  /// lần tự động đầu (lúc chuyển trạng thái) không tìm thấy ai (chưa có tài xế online).
  Future<void> findDriver(String orderId) async {
    await _api.post('/orders/$orderId/find-driver');
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
