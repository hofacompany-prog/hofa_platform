import '../core/api_client.dart';
import '../models/app_notification.dart';

class NotificationRepository {
  final _api = ApiClient.instance;

  Future<List<AppNotification>> list({int limit = 50, int offset = 0, String? category}) async {
    final list = await _api.get('/notifications', query: {
      'limit': limit,
      'offset': offset,
      if (category != null) 'category': category,
    }) as List;
    return list
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> unreadCount({String? category}) async {
    final data = await _api.get(
      '/notifications/unread-count',
      query: {if (category != null) 'category': category},
    ) as Map<String, dynamic>;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) async {
    await _api.patch('/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await _api.post('/notifications/read-all');
  }
}
