/// 1 dòng hộp thư THẬT của 1 người nhận (bảng notifications, GET /admin/notifications/inbox)
/// — khác AdminNotification (đó là log 1 đợt gửi, cái này là dòng người nhận thật sự thấy
/// trong app của họ). Chỉ xem theo từng cửa hàng (merchant_id bắt buộc ở API), gộp cả thông
/// báo đơn hàng tự động lẫn thông báo admin gửi tay cho cửa hàng đó.
class NotificationInboxItem {
  final String id;
  final String userId;
  final String recipientName;
  final String title;
  final String body;
  final String category;
  final DateTime? readAt;
  final DateTime createdAt;

  NotificationInboxItem({
    required this.id,
    required this.userId,
    required this.recipientName,
    required this.title,
    required this.body,
    required this.category,
    this.readAt,
    required this.createdAt,
  });

  bool get isRead => readAt != null;

  factory NotificationInboxItem.fromJson(Map<String, dynamic> json) => NotificationInboxItem(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        recipientName: json['recipient_name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        category: json['category'] as String? ?? 'system',
        readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at'] as String) : null,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}
