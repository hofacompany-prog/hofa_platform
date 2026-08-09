import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/push_service.dart';
import '../../models/app_notification.dart';
import '../../providers/app_providers.dart';

/// Hộp thư thông báo trong app — lưu lại MỌI thông báo đã gửi (đơn hàng đổi trạng thái,
/// admin gửi tay...), độc lập với việc push FCM có thật sự tới máy hay không (thiết bị
/// chưa cấp quyền/không có push_token vẫn xem lại được ở đây). Bấm vào 1 dòng tự đánh dấu
/// đã đọc rồi điều hướng đúng như khi bấm push thật (dùng lại PushService.handleData).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _markingAll = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(notificationsPagedProvider.notifier).loadMore();
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      await ref.read(notificationRepoProvider).markAllRead();
      ref.invalidate(notificationsPagedProvider);
      ref.invalidate(unreadNotificationCountProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openNotification(AppNotification n) async {
    if (!n.isRead) {
      // Không chờ API xong mới điều hướng — cập nhật giao diện + gọi API song song,
      // cảm giác bấm vào phải nhanh, lỗi mạng thoáng qua không đáng chặn điều hướng.
      ref.read(notificationRepoProvider).markRead(n.id).catchError((_) {});
      ref.invalidate(notificationsPagedProvider);
      ref.invalidate(unreadNotificationCountProvider);
    }
    PushService.instance.handleData(n.data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notificationsState = ref.watch(notificationsPagedProvider);
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
          ref.invalidate(notificationsPagedProvider);
          ref.invalidate(unreadNotificationCountProvider);
        },
        child: notificationsState.isInitialLoading
            ? const Center(child: CircularProgressIndicator())
            : notificationsState.error != null && notificationsState.items.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text('Lỗi: ${notificationsState.error}')),
                      ),
                    ],
                  )
                : notificationsState.items.isEmpty
                    ? ListView(
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
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: notificationsState.items.length +
                            (notificationsState.hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          if (i == notificationsState.items.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          }
                          final n = notificationsState.items[i];
                          return Material(
                            color: n.isRead
                                ? null
                                : theme.colorScheme.primary.withValues(alpha: 0.05),
                            child: ListTile(
                              onTap: () => _openNotification(n),
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
                                  Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis),
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
                      ),
      ),
    );
  }
}
