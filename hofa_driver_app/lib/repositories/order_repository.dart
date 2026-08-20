import '../core/api_client.dart';
import '../models/order.dart';
import '../models/chat_message.dart';

class OrderRepository {
  final _api = ApiClient.instance;

  Future<Order> get(String id) async =>
      Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

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
