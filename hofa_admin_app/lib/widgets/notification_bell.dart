import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/notification_providers.dart';

/// Icon chuông + số chưa đọc — hộp thư CỦA CHÍNH ADMIN (đơn cần xác nhận thanh toán, tài
/// xế/cửa hàng yêu cầu nạp/rút ví). Đặt trong admin_shell.dart để hiện ở mọi màn.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: 'Thông báo',
      onPressed: () => context.push('/my-notifications'),
      icon: unread > 0
          ? Badge(
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            )
          : const Icon(Icons.notifications_outlined),
    );
  }
}
