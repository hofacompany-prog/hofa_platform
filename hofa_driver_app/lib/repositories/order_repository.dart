import '../core/api_client.dart';
import '../models/order.dart';
import '../models/chat_message.dart';

class OrderRepository {
  final _api = ApiClient.instance;

  Future<Order> get(String id) async =>
      Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

  // ---- Nhắn tin trong đơn — xem hofa-db/74_order_chat.sql ----

  Future<List<ChatMessage>> chatMessages(
    String orderId,
    ChatChannel channel,
  ) async {
    final list =
        await _api.get(
              '/orders/$orderId/messages',
              query: {'channel': channel.apiValue},
            )
            as List;
    return list
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
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
