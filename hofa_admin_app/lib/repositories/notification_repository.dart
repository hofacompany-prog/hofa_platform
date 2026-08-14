import '../core/api_client.dart';
import '../models/app_notification.dart';

/// Hộp thư CỦA CHÍNH ADMIN (role admin cũng là 1 user bình thường ở bảng notifications) —
/// khác AdminRepository.notificationInbox (admin xem hộp thư của user KHÁC).
class NotificationRepository {
  final _api = ApiClient.instance;

  Future<List<AppNotification>> list({int limit = 50, String? category}) async {
    final list =
        await _api.get(
              '/notifications',
              query: {
                'limit': limit,
                if (category != null) 'category': category,
              },
            )
            as List;
    return list
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> unreadCount({String? category}) async {
    final data =
        await _api.get(
              '/notifications/unread-count',
              query: {if (category != null) 'category': category},
            )
            as Map<String, dynamic>;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) async {
    await _api.patch('/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await _api.post('/notifications/read-all');
  }
}
