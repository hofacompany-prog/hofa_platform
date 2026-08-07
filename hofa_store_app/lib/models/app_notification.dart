/// 1 thông báo trong hộp thư của app — bản ghi bền (khác push tức thời qua FCM), lưu lại
/// dù thiết bị không có push_token/chưa cấp quyền thông báo. [data] là đúng payload đã gửi
/// qua FCM (type, order_id, screen...) — dùng lại được PushService.instance.handleData(data)
/// để điều hướng khi bấm vào 1 dòng, không cần viết lại logic điều hướng lần 2.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.data = const {},
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
        readAt: json['read_at'] != null
            ? DateTime.tryParse(json['read_at'] as String)
            : null,
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}
