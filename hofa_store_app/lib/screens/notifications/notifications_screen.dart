import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/push_service.dart';
import '../../models/app_notification.dart';
import '../../providers/notification_providers.dart';

/// Hộp thư thông báo trong app — lưu lại MỌI thông báo đã gửi (đơn mới, tự động xác nhận,
/// admin gửi tay...), độc lập với việc push FCM có thật sự tới máy hay không (thiết bị chưa
/// cấp quyền/không có push_token vẫn xem lại được ở đây). Bấm vào 1 dòng tự đánh dấu đã đọc
/// rồi điều hướng đúng như khi bấm push thật (dùng lại PushService.handleData).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _markingAll = false;

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      await ref.read(notificationRepoProvider).markAllRead();
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationCountProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openNotification(AppNotification n) async {
    if (!n.isRead) {
      ref.read(notificationRepoProvider).markRead(n.id).catchError((_) {});
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationCountProvider);
    }
    PushService.instance.handleData(n.data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final hasUnread = (unreadAsync.valueOrNull ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: _markingAll
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Đọc tất cả'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          ref.invalidate(unreadNotificationCountProvider);
        },
        child: notificationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Lỗi: $e'))),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80),
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none, size: 56, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có thông báo nào',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = items[i];
                return Material(
                  color: n.isRead ? null : theme.colorScheme.primary.withValues(alpha: 0.05),
                  child: ListTile(
                    onTap: () => _openNotification(n),
                    leading: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: CircleAvatar(
                        radius: 5,
                        backgroundColor: n.isRead ? Colors.transparent : theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      n.title,
                      style: TextStyle(fontWeight: n.isRead ? FontWeight.normal : FontWeight.w700),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(
                          formatDateTime(n.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
