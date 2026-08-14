/// App tài xế chỉ dùng kênh customer_driver — xem hofa-db/74_order_chat.sql.
enum ChatChannel { customerDriver, customerMerchant }

extension ChatChannelX on ChatChannel {
  String get apiValue => switch (this) {
    ChatChannel.customerDriver => 'customer_driver',
    ChatChannel.customerMerchant => 'customer_merchant',
  };
}

class ChatMessage {
  final String id;
  final String orderId;
  final String channel;
  final String senderId;
  final String senderRole;
  final String? body;
  final String? imageUrl;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.orderId,
    required this.channel,
    required this.senderId,
    required this.senderRole,
    this.body,
    this.imageUrl,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    orderId: json['order_id'] as String,
    channel: json['channel'] as String,
    senderId: json['sender_id'] as String,
    senderRole: json['sender_role'] as String? ?? '',
    body: json['body'] as String?,
    imageUrl: json['image_url'] as String?,
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );
}

/// Số giờ được nhắn tin thêm sau khi đơn giao xong (admin cấu hình) — hết giờ thì ẩn lối vào
/// nhắn tin, xem hofa-db/74_order_chat.sql.
class ChatSettings {
  final int hoursAfterDelivered;

  ChatSettings({required this.hoursAfterDelivered});

  factory ChatSettings.fromJson(Map<String, dynamic> json) => ChatSettings(
    hoursAfterDelivered: (json['hours_after_delivered'] as num?)?.toInt() ?? 1,
  );

  factory ChatSettings.fallback() => ChatSettings(hoursAfterDelivered: 1);
}

/// Còn mở nhắn tin không — mọi trạng thái đang vận hành (trừ cancelled/refunded) luôn mở; đã
/// giao/hoàn tất thì mở thêm đúng [hoursAfterDelivered] giờ tính từ [deliveredAt].
bool isChatWindowOpen({
  required String status,
  DateTime? deliveredAt,
  required int hoursAfterDelivered,
}) {
  if (status == 'cancelled' || status == 'refunded') return false;
  if (status == 'delivered' || status == 'completed') {
    if (deliveredAt == null) return false;
    return DateTime.now().isBefore(
      deliveredAt.add(Duration(hours: hoursAfterDelivered)),
    );
  }
  return true;
}
