import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/push_service.dart';
import '../../models/app_notification.dart';
import '../../providers/notification_providers.dart';

/// Tab "Tất cả" trước, rồi tới các danh mục thật — order luôn do hệ thống tự gắn cho thông
/// báo đơn hàng/chuyến giao, promotion/ad/system do admin tự chọn lúc gửi tay (màn "Thông
/// báo" ở web admin). null = "Tất cả" (không lọc).
const _tabCategories = [null, 'order', 'promotion', 'ad', 'system'];

/// Hộp thư thông báo trong app, chia theo danh mục (tab) — lưu lại MỌI thông báo đã gửi,
/// độc lập với việc push FCM có thật sự tới máy hay không (thiết bị chưa cấp quyền/không có
/// push_token vẫn xem lại được ở đây). Bấm vào 1 dòng tự đánh dấu đã đọc rồi điều hướng đúng
/// như khi bấm push thật (dùng lại PushService.handleData) — với thông báo đơn hàng, đây
/// cũng là 1 trong 2 cách đánh dấu đã đọc (cách kia là bấm thẳng push ngoài màn hình chính).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCategories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _invalidateAll() {
    for (final c in _tabCategories) {
      ref.invalidate(notificationsProvider(c));
    }
    ref.invalidate(unreadNotificationCountProvider);
    ref.invalidate(unreadOrderCountProvider);
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      await ref.read(notificationRepoProvider).markAllRead();
      _invalidateAll();
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
      _invalidateAll();
    }
    PushService.instance.handleData(n.data);
  }

  @override
  Widget build(BuildContext context) {
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final hasUnread = (unreadAsync.valueOrNull ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabCategories
              .map((c) => Tab(text: c == null ? 'Tất cả' : notificationCategoryLabels[c] ?? c))
              .toList(),
        ),
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
      body: TabBarView(
        controller: _tabController,
        children: _tabCategories
            .map((category) => _NotificationList(
                  category: category,
                  onTap: _openNotification,
                  onRefresh: () async {
                    ref.invalidate(notificationsProvider(category));
                    ref.invalidate(unreadNotificationCountProvider);
                    ref.invalidate(unreadOrderCountProvider);
                  },
                ))
            .toList(),
      ),
    );
  }
}

class _NotificationList extends ConsumerWidget {
  final String? category;
  final void Function(AppNotification) onTap;
  final Future<void> Function() onRefresh;

  const _NotificationList({
    required this.category,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notificationsAsync = ref.watch(notificationsProvider(category));

    return RefreshIndicator(
      onRefresh: onRefresh,
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
                  onTap: () => onTap(n),
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
                      Row(
                        children: [
                          if (category == null) ...[
                            Chip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              label: Text(
                                notificationCategoryLabels[n.category] ?? n.category,
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            formatDateTime(n.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ],
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
    );
  }
}
