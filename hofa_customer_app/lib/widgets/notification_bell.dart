import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/require_login.dart';
import '../providers/app_providers.dart';

/// Icon chuông + số chưa đọc — đặt ở AppBar của màn chính, bấm vào mở hộp thư thông báo.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: 'Thông báo',
      onPressed: () async {
        if (!await requireLogin(context)) return;
        if (context.mounted) context.push('/notifications');
      },
      icon: unread > 0
          ? Badge(
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            )
          : const Icon(Icons.notifications_outlined),
    );
  }
}
