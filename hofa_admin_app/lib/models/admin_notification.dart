/// 1 lượt thông báo đẩy admin đã gửi cho khách hàng — xem lịch sử ở màn Thông báo.
class AdminNotification {
  final String id;
  final String title;
  final String body;
  final String target;
  final int sentCount;
  final int totalCount;
  final DateTime createdAt;
  final String? createdByName;
  final List<String> recipientNames;

  AdminNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
    required this.sentCount,
    required this.totalCount,
    required this.createdAt,
    this.createdByName,
    this.recipientNames = const [],
  });

  factory AdminNotification.fromJson(Map<String, dynamic> json) =>
      AdminNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        target: json['target'] as String? ?? 'all_customers',
        sentCount: (json['sent_count'] as num?)?.toInt() ?? 0,
        totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        createdByName: json['created_by_name'] as String?,
        recipientNames:
            (json['recipient_names'] as List?)?.cast<String>() ?? const [],
      );
}
