/// 1 thông báo trong hộp thư CỦA CHÍNH ADMIN — bản ghi bền (khác push tức thời qua FCM), lưu
/// lại dù thiết bị không có push_token/chưa cấp quyền thông báo. [data] là đúng payload đã gửi
/// qua FCM (type, kind, screen...) — dùng lại được PushService.instance.handleData(data) để
/// điều hướng khi bấm vào 1 dòng. Khác NotificationInboxItem (models/notification_inbox_item.dart)
/// — đó là admin XEM hộp thư của user khác (màn "Thông báo" > "Hộp thư theo cửa hàng").
class AppNotification {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String category;
  final DateTime? readAt;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.data = const {},
    this.category = 'system',
    this.readAt,
    required this.createdAt,
  });

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        category: json['category'] as String? ?? 'system',
        readAt: json['read_at'] != null
            ? DateTime.tryParse(json['read_at'] as String)
            : null,
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}
