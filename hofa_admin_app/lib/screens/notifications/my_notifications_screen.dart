import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/push_service.dart';
import '../../models/app_notification.dart';
import '../../providers/notification_providers.dart';
import '../../widgets/stat_card.dart';

/// Hộp thư CỦA CHÍNH ADMIN — đơn cần xác nhận thanh toán, tài xế/cửa hàng yêu cầu nạp/rút ví
/// (xem server/src/push.js#notifyAdmins). Khác /notifications (NotificationsScreen) — màn đó
/// là công cụ admin GỬI thông báo cho khách/cửa hàng/tài xế và xem hộp thư của HỌ, không phải
/// hộp thư của admin.
class MyNotificationsScreen extends ConsumerWidget {
  const MyNotificationsScreen({super.key});

  Future<void> _open(
    WidgetRef ref,
    BuildContext context,
    AppNotification n,
  ) async {
    if (!n.isRead) {
      ref.read(notificationRepoProvider).markRead(n.id).catchError((_) {});
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationCountProvider);
    }
    PushService.instance.handleData(n.data);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () async {
                await ref.read(notificationRepoProvider).markAllRead();
                ref.invalidate(notificationsProvider);
                ref.invalidate(unreadNotificationCountProvider);
              },
              child: const Text('Đọc tất cả'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          ref.invalidate(unreadNotificationCountProvider);
        },
        child: itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Lỗi: $e')),
              ),
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
                        Icon(
                          Icons.notifications_none,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có thông báo nào',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: StatCard(
                      label: 'Tổng thông báo',
                      value: '${items.length}',
                      icon: Icons.notifications_outlined,
                    ),
                  );
                }
                final n = items[i];
                return Material(
                  color: n.isRead
                      ? null
                      : theme.colorScheme.primary.withValues(alpha: 0.05),
                  child: ListTile(
                    onTap: () => _open(ref, context, n),
                    leading: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: CircleAvatar(
                        radius: 5,
                        backgroundColor: n.isRead
                            ? Colors.transparent
                            : theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      n.title,
                      style: TextStyle(
                        fontWeight: n.isRead
                            ? FontWeight.normal
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.body),
                        const SizedBox(height: 4),
                        Text(
                          formatDateTime(n.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
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
